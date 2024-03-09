// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import "./lib/Multicall.sol";
import "./interfaces/IAutoYield.sol";

/*
    ___         __    __  ___      __    __
   /   | __  __/ /____\ \/ (_)__  / /___/ /
  / /| |/ / / / __/ __ \  / / _ \/ / __  /
 / ___ / /_/ / /_/ /_/ / / /  __/ / /_/ /
/_/  |_\__,_/\__/\____/_/_/\___/_/\__,_/

*/
contract AutoYield is IAutoYield, ReentrancyGuard, Multicall, Ownable {
    using SafeMath for uint256;

    uint128 constant Q64 = 2**64;
    uint128 constant Q96 = 2**96;

    // max reward
    uint64 constant public MAX_REWARD_X64 = uint64(Q64 / 50); // 2%

    // max positions
    uint32 constant public MAX_POSITIONS_PER_ADDRESS = 100;

    uint32 public constant MIN_TWAP_SECONDS = 60; // 1 minute
    uint32 public constant MAX_TWAP_TICK_DIFFERENCE = 200; // 2%

    // changable config values
    uint64 public override totalRewardX64 = MAX_REWARD_X64; // 2%
    uint64 public override compounderRewardX64 = MAX_REWARD_X64 / 2; // 1%
    uint16 public override maxTWAPTickDifference = 100; // 1%
    uint32 public override TWAPSeconds = 60;

    address public swapRouterReBalance;

    // uniswap v3 components
    address public withdrawer;
    IUniswapV3Factory public override factory;
    INonfungiblePositionManager public override npm;
    ISwapRouter public override swapRouter;
    IWETH9 public immutable override weth;

    // configured tokens
    mapping (uint256 => RangePositionConfig) public rangePositionConfigs;
    // configurable by owner
    mapping(address => bool) public operators;
    mapping(uint256 => address) public override ownerOf;
    mapping(address => uint256[]) public override accountTokens;
    mapping(address => mapping(address => uint256)) public override accountBalances;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, ISwapRouter _swapRouter, address _operator, address _withdrawer, uint32 _TWAPSeconds, uint16 _maxTWAPTickDifference)
    {
        npm = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
        factory = IUniswapV3Factory(npm.factory());
        weth = IWETH9(npm.WETH9());

        swapRouterReBalance = address(_swapRouter);

        emit SwapRouterChanged(swapRouterReBalance);

        setOperator(_operator, true);
        setWithdrawer(_withdrawer);
        setTWAPConfig(_maxTWAPTickDifference, _TWAPSeconds);
    }

    /**
     * @notice Management method to lower reward or change ratio between total and compounder reward (onlyOwner)
     * @param _totalRewardX64 new total reward (can't be higher than current total reward)
     * @param _compounderRewardX64 new compounder reward
     */
    function setReward(uint64 _totalRewardX64, uint64 _compounderRewardX64) external override onlyOwner {
        require(_totalRewardX64 <= totalRewardX64, ">totalRewardX64");
        require(_compounderRewardX64 <= _totalRewardX64, "compounderRewardX64>totalRewardX64");
        totalRewardX64 = _totalRewardX64;
        compounderRewardX64 = _compounderRewardX64;
        emit RewardUpdated(msg.sender, _totalRewardX64, _compounderRewardX64);
    }

    /**
    * @notice Owner controlled function to change swap router (onlyOwner)
     * @param _swapRouterReBalance new swap router address
     */
    function setSwapRouterReBalance(address _swapRouterReBalance) external onlyOwner {
        emit SwapRouterChanged(_swapRouterReBalance);
        swapRouterReBalance = _swapRouterReBalance;
    }

    /**
     * @notice Owner controlled function to set withdrawer address
     * @param _withdrawer withdrawer
     */
    function setWithdrawer(address _withdrawer) public onlyOwner {
        emit WithdrawerChanged(_withdrawer);
        withdrawer = _withdrawer;
    }

    /**
     * @notice Owner controlled function to activate/deactivate operator address
     * @param _operator operator
     * @param _active active or not
     */
    function setOperator(address _operator, bool _active) public onlyOwner {
        emit OperatorChanged(_operator, _active);
        operators[_operator] = _active;
    }

    /**
    * @notice Management method to change the max tick difference from twap to allow swaps (onlyOwner)
     * @param _maxTWAPTickDifference new max tick difference
     */
    function setTWAPConfig(uint16 _maxTWAPTickDifference, uint32 _TWAPSeconds) public onlyOwner {
        if (_TWAPSeconds < MIN_TWAP_SECONDS) {
            revert('InvalidConfig');
        }
        if (_maxTWAPTickDifference > MAX_TWAP_TICK_DIFFERENCE) {
            revert('InvalidConfig');
        }

        TWAPSeconds = _TWAPSeconds;
        maxTWAPTickDifference = _maxTWAPTickDifference;
        emit TWAPConfigUpdated(msg.sender, _maxTWAPTickDifference, _TWAPSeconds);
    }

    /**
     * @notice Withdraws token balance
     * @param tokens Addresses of tokens to withdraw
     * @param to Address to send to
     */
    function withdrawBalances(address[] calldata tokens, address to) external override {

        if (msg.sender != withdrawer) {
            revert('Unauthorized');
        }

        uint i;
        uint count = tokens.length;
        for(;i < count;++i) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                _transferToken(to, IERC20(tokens[i]), balance, true);
            }
        }
    }

    /**
     * @notice Withdraws ETH balance
     * @param to Address to send to
     */
    function withdrawETH(address to) external {

        if (msg.sender != withdrawer) {
            revert('Unauthorized');
        }

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent,) = to.call{value: balance}("");
            if (!sent) {
                revert('EtherSendFailed');
            }
        }
    }

    /**
     * @notice Adjust token (must be in correct state)
     * Can only be called only from configured operator account
     * Swap needs to be done with max price difference from current pool price - otherwise reverts
     */
    function reBalance(RangeExecuteParams calldata params) external {

        if (!operators[msg.sender]) {
            revert('Unauthorized');
        }

        RangeExecuteState memory state;
        RangePositionConfig memory config = rangePositionConfigs[params.tokenId];

        if (config.lowerTickDelta == config.upperTickDelta) {
            revert('NotConfigured');
        }

        if (config.onlyFees && params.rewardX64 > config.maxRewardX64 || !config.onlyFees && params.rewardX64 > config.maxRewardX64) {
            revert('ExceedsMaxReward');
        }

        // get position info
        (,, state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, state.liquidity, , , , ) =  npm.positions(params.tokenId);

        if (state.liquidity != params.liquidity) {
            revert('LiquidityChanged');
        }

        (state.amount0, state.amount1, state.feeAmount0, state.feeAmount1) = _decreaseFullLiquidityAndCollect(params.tokenId, state.liquidity, params.amountRemoveMin0, params.amountRemoveMin1, params.deadline);

        // if only fees reward is removed before adding
        if (config.onlyFees) {
            state.protocolReward0 = state.feeAmount0 * params.rewardX64 / Q64;
            state.protocolReward1 = state.feeAmount1 * params.rewardX64 / Q64;
            state.amount0 -= state.protocolReward0;
            state.amount1 -= state.protocolReward1;
        }

        if (params.swap0To1 && params.amountIn > state.amount0 || !params.swap0To1 && params.amountIn > state.amount1) {
            revert('SwapAmountTooLarge');
        }

        // get pool info
        state.pool = _getPool(state.token0, state.token1, state.fee);

        // check oracle for swap
        (state.amountOutMin,state.currentTick,,) = _validateSwap(params.swap0To1, params.amountIn, state.pool, TWAPSeconds, maxTWAPTickDifference, params.swap0To1 ? config.token0SlippageX64 : config.token1SlippageX64);

        if (state.currentTick < state.tickLower - config.lowerTickLimit || state.currentTick >= state.tickUpper + config.upperTickLimit) {

            int24 tickSpacing = _getTickSpacing(state.fee);
            int24 baseTick = state.currentTick - (((state.currentTick % tickSpacing) + tickSpacing) % tickSpacing);

            // check if new range same as old range
            if (baseTick + config.lowerTickDelta == state.tickLower && baseTick + config.upperTickDelta == state.tickUpper) {
                revert('SameRange');
            }

            (state.amountInDelta, state.amountOutDelta) = _swap(params.swap0To1 ? IERC20(state.token0) : IERC20(state.token1), params.swap0To1 ? IERC20(state.token1) : IERC20(state.token0), params.amountIn, state.amountOutMin, params.swapData);

            state.amount0 = params.swap0To1 ? state.amount0 - state.amountInDelta : state.amount0 + state.amountOutDelta;
            state.amount1 = params.swap0To1 ? state.amount1 + state.amountOutDelta : state.amount1 - state.amountInDelta;

            // max amount to add - removing max potential fees (if config.onlyFees - the have been removed already)
            state.maxAddAmount0 = config.onlyFees ? state.amount0 : state.amount0 * Q64 / (params.rewardX64 + Q64);
            state.maxAddAmount1 = config.onlyFees ? state.amount1 : state.amount1 * Q64 / (params.rewardX64 + Q64);

            INonfungiblePositionManager.MintParams memory mintParams =
                                INonfungiblePositionManager.MintParams(
                    address(state.token0),
                    address(state.token1),
                    state.fee,
                    int24(baseTick + config.lowerTickDelta), // reverts if out of valid range
                    int24(baseTick + config.upperTickDelta), // reverts if out of valid range
                    state.maxAddAmount0,
                    state.maxAddAmount1,
                    0,
                    0,
                    address(this), // is sent to real recipient aftwards
                    params.deadline
                );

            // approve npm
            SafeERC20.safeApprove(IERC20(state.token0), address(npm), state.maxAddAmount0);
            SafeERC20.safeApprove(IERC20(state.token1), address(npm), state.maxAddAmount1);

            // mint is done to address(this) first - its not a safemint
            (state.newTokenId,,state.amountAdded0,state.amountAdded1) = npm.mint(mintParams);

            // remove remaining approval
            SafeERC20.safeApprove(IERC20(state.token0), address(npm), 0);
            SafeERC20.safeApprove(IERC20(state.token1), address(npm), 0);

            state.owner = npm.ownerOf(params.tokenId);

            // send it to current owner
            npm.safeTransferFrom(address(this), state.owner, state.newTokenId);

            // protocol reward is calculated based on added amount (to incentivize optimal swap done by operator)
            if (!config.onlyFees) {
                state.protocolReward0 = state.amountAdded0 * params.rewardX64 / Q64;
                state.protocolReward1 = state.amountAdded1 * params.rewardX64 / Q64;
                state.amount0 -= state.protocolReward0;
                state.amount1 -= state.protocolReward1;
            }

            // send leftover to owner
            if (state.amount0 - state.amountAdded0 > 0) {
                _transferToken(state.owner, IERC20(state.token0), state.amount0 - state.amountAdded0, true);
            }
            if (state.amount1 - state.amountAdded1 > 0) {
                _transferToken(state.owner, IERC20(state.token1), state.amount1 - state.amountAdded1, true);
            }

            // copy token config for new token
            rangePositionConfigs[state.newTokenId] = config;
            emit RangePositionConfigured(
                state.newTokenId,
                config.lowerTickLimit,
                config.upperTickLimit,
                config.lowerTickDelta,
                config.upperTickDelta,
                config.token0SlippageX64,
                config.token1SlippageX64,
                config.onlyFees,
                config.maxRewardX64
            );

            // delete config for old position
            delete rangePositionConfigs[params.tokenId];
            emit RangePositionConfigured(params.tokenId, 0, 0, 0, 0, 0, 0, false, 0);

            emit RangeChanged(params.tokenId, state.newTokenId);

        } else {
            revert('NotReady');
        }
    }

    // function to configure a token to be used with this runner
    // it needs to have approvals set for this contract beforehand
    function configToken(uint256 tokenId, RangePositionConfig calldata config) external {
        address owner = npm.ownerOf(tokenId);
        if (owner != msg.sender) {
            revert('Unauthorized');
        }

        // lower tick must be always below or equal to upper tick - if they are equal - range adjustment is deactivated
        if (config.lowerTickDelta > config.upperTickDelta) {
            revert('InvalidConfig');
        }

        rangePositionConfigs[tokenId] = config;

        emit RangePositionConfigured(
            tokenId,
            config.lowerTickLimit,
            config.upperTickLimit,
            config.lowerTickDelta,
            config.upperTickDelta,
            config.token0SlippageX64,
            config.token1SlippageX64,
            config.onlyFees,
            config.maxRewardX64
        );
    }

    /**
     * @dev When receiving a Uniswap V3 NFT, deposits token with `from` as owner
     */
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override nonReentrant returns (bytes4) {
        require(msg.sender == address(npm), "!univ3 pos");

        _addToken(tokenId, from);
        emit TokenDeposited(from, tokenId);
        return this.onERC721Received.selector;
    }

    /**
     * @notice Returns amount of NFTs for a given account
     * @param account Address of account
     * @return balance amount of NFTs for account
     */
    function balanceOf(address account) override external view returns (uint256 balance) {
        return accountTokens[account].length;
    }

    // state used during autocompound execution
    struct AutoCompoundState {
        uint256 amount0;
        uint256 amount1;
        uint256 maxAddAmount0;
        uint256 maxAddAmount1;
        uint256 amount0Fees;
        uint256 amount1Fees;
        uint256 priceX96;
        address tokenOwner;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    /**
     * @notice Autocompounds for a given NFT (anyone can call this and gets a percentage of the fees)
     * @param params Autocompound specific parameters (tokenId, ...)
     * @return reward0 Amount of token0 caller recieves
     * @return reward1 Amount of token1 caller recieves
     * @return compounded0 Amount of token0 that was compounded
     * @return compounded1 Amount of token1 that was compounded
     */
    function autoCompound(AutoCompoundParams memory params) 
        override 
        external 
        nonReentrant
        returns (uint256 reward0, uint256 reward1, uint256 compounded0, uint256 compounded1)
    {
        require(ownerOf[params.tokenId] != address(0), "!found");

        AutoCompoundState memory state;

        // collect fees
        (state.amount0, state.amount1) = npm.collect(
            INonfungiblePositionManager.CollectParams(params.tokenId, address(this), type(uint128).max, type(uint128).max)
        );

        // get position info
        (, , state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, , , , , ) = 
            npm.positions(params.tokenId);

        state.tokenOwner = ownerOf[params.tokenId];

        // add previous balances from given tokens
        state.amount0 = state.amount0.add(accountBalances[state.tokenOwner][state.token0]);
        state.amount1 = state.amount1.add(accountBalances[state.tokenOwner][state.token1]);

        // only if there are balances to work with - start autocompounding process
        if (state.amount0 > 0 || state.amount1 > 0) {

            SwapParams memory swapParams = SwapParams(
                state.token0, 
                state.token1, 
                state.fee, 
                state.tickLower, 
                state.tickUpper, 
                state.amount0, 
                state.amount1, 
                block.timestamp, 
                params.rewardConversion, 
                state.tokenOwner == msg.sender, 
                params.doSwap
            );
    
            // checks oracle for fair price - swaps to position ratio (considering estimated reward) - calculates max amount to be added
            (state.amount0, state.amount1, state.priceX96, state.maxAddAmount0, state.maxAddAmount1) = 
                _swapToPriceRatio(swapParams);

            // deposit liquidity into tokenId
            if (state.maxAddAmount0 > 0 || state.maxAddAmount1 > 0) {
                (, compounded0, compounded1) = npm.increaseLiquidity(
                    INonfungiblePositionManager.IncreaseLiquidityParams(
                        params.tokenId,
                        state.maxAddAmount0,
                        state.maxAddAmount1,
                        0,
                        0,
                        block.timestamp
                    )
                );
            }

            // fees are always calculated based on added amount
            // only calculate them when not tokenOwner
            if (state.tokenOwner != msg.sender) {
                if (params.rewardConversion == RewardConversion.NONE) {
                    state.amount0Fees = compounded0.mul(totalRewardX64).div(Q64);
                    state.amount1Fees = compounded1.mul(totalRewardX64).div(Q64);
                } else {
                    // calculate total added - derive fees
                    uint addedTotal0 = compounded0.add(compounded1.mul(Q96).div(state.priceX96));
                    if (params.rewardConversion == RewardConversion.TOKEN_0) {
                        state.amount0Fees = addedTotal0.mul(totalRewardX64).div(Q64);
                        // if there is not enough token0 to pay fee - pay all there is
                        if (state.amount0Fees > state.amount0.sub(compounded0)) {
                            state.amount0Fees = state.amount0.sub(compounded0);
                        }
                    } else {
                        state.amount1Fees = addedTotal0.mul(state.priceX96).div(Q96).mul(totalRewardX64).div(Q64);
                        // if there is not enough token1 to pay fee - pay all there is
                        if (state.amount1Fees > state.amount1.sub(compounded1)) {
                            state.amount1Fees = state.amount1.sub(compounded1);
                        }
                    }
                }
            }

            // calculate remaining tokens for owner
            _setBalance(state.tokenOwner, state.token0, state.amount0.sub(compounded0).sub(state.amount0Fees));
            _setBalance(state.tokenOwner, state.token1, state.amount1.sub(compounded1).sub(state.amount1Fees));

            // distribute fees - handle 2 cases (nft owner - no protocol reward / anyone else)
            if (state.tokenOwner == msg.sender) {
                reward0 = 0;
                reward1 = 0;
            } else {
                uint64 protocolRewardX64 = totalRewardX64 - compounderRewardX64;
                uint256 protocolFees0 = state.amount0Fees.mul(protocolRewardX64).div(totalRewardX64);
                uint256 protocolFees1 = state.amount1Fees.mul(protocolRewardX64).div(totalRewardX64);

                reward0 = state.amount0Fees.sub(protocolFees0);
                reward1 = state.amount1Fees.sub(protocolFees1);

                _increaseBalance(msg.sender, state.token0, reward0);
                _increaseBalance(msg.sender, state.token1, reward1);
                _increaseBalance(owner(), state.token0, protocolFees0);
                _increaseBalance(owner(), state.token1, protocolFees1);
            }
        }

        if (params.withdrawReward) {
            _withdrawFullBalances(state.token0, state.token1, msg.sender);
        }

        emit AutoCompounded(msg.sender, params.tokenId, compounded0, compounded1, reward0, reward1, state.token0, state.token1);
    }

    /**
     * @notice Special method to decrease liquidity and collect decreased amount - can only be called by the NFT owner
     * @dev Needs to do collect at the same time, otherwise the available amount would be autocompoundable for other positions
     * @param params DecreaseLiquidityAndCollectParams which are forwarded to the Uniswap V3 NonfungiblePositionManager
     * @return amount0 amount of token0 removed and collected
     * @return amount1 amount of token1 removed and collected
     */
    function decreaseLiquidityAndCollect(DecreaseLiquidityAndCollectParams calldata params) 
        override 
        external  
        nonReentrant 
        returns (uint256 amount0, uint256 amount1) 
    {
        require(ownerOf[params.tokenId] == msg.sender, "!owner");
        (amount0, amount1) = npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(
                params.tokenId, 
                params.liquidity, 
                params.amount0Min, 
                params.amount1Min,
                params.deadline
            )
        );

        INonfungiblePositionManager.CollectParams memory collectParams = 
            INonfungiblePositionManager.CollectParams(
                params.tokenId, 
                params.recipient,
                uint128(amount0),
                uint128(amount1)
            );

        npm.collect(collectParams);
    }

    /**
     * @notice Forwards collect call to NonfungiblePositionManager - can only be called by the NFT owner
     * @param params INonfungiblePositionManager.CollectParams which are forwarded to the Uniswap V3 NonfungiblePositionManager
     * @return amount0 amount of token0 collected
     * @return amount1 amount of token1 collected
     */
    function collect(INonfungiblePositionManager.CollectParams calldata params) 
        override 
        external
        nonReentrant 
        returns (uint256 amount0, uint256 amount1) 
    {
        require(ownerOf[params.tokenId] == msg.sender, "!owner");
        return npm.collect(params);
    }

    /**
     * @notice Removes a NFT from the protocol and safe transfers it to address to
     * @param tokenId TokenId of token to remove
     * @param to Address to send to
     * @param withdrawBalances_ When true sends the available balances for token0 and token1 as well
     * @param data data which is sent with the safeTransferFrom call
     */
    function withdrawToken(
        uint256 tokenId,
        address to,
        bool withdrawBalances_,
        bytes memory data
    ) external override nonReentrant {
        require(to != address(this), "to==this");
        require(ownerOf[tokenId] == msg.sender, "!owner");

        _removeToken(msg.sender, tokenId);
        npm.safeTransferFrom(address(this), to, tokenId, data);
        emit TokenWithdrawn(msg.sender, to, tokenId);

        if (withdrawBalances_) {
            (, , address token0, address token1, , , , , , , , ) = npm.positions(tokenId);
            _withdrawFullBalances(token0, token1, to);
        }
    }

    /**
     * @notice Withdraws token balance for a address and token
     * @param token Address of token to withdraw
     * @param to Address to send to
     * @param amount amount to withdraw
     */
    function withdrawBalance(address token, address to, uint256 amount) external override nonReentrant {
        require(amount > 0, "amount==0");
        uint256 balance = accountBalances[msg.sender][token];
        _withdrawBalanceInternal(token, to, balance, amount);
    }

    function _increaseBalance(address account, address token, uint256 amount) internal {
        accountBalances[account][token] = accountBalances[account][token].add(amount);
        emit BalanceAdded(account, token, amount);
    }

    function _setBalance(address account, address token, uint256 amount) internal {
        uint currentBalance = accountBalances[account][token];
        
        if (amount > currentBalance) {
            accountBalances[account][token] = amount;
            emit BalanceAdded(account, token, amount.sub(currentBalance));
        } else if (amount < currentBalance) {
            accountBalances[account][token] = amount;
            emit BalanceRemoved(account, token, currentBalance.sub(amount));
        }
    }

    function _withdrawFullBalances(address token0, address token1, address to) internal {
        uint256 balance0 = accountBalances[msg.sender][token0];
        if (balance0 > 0) {
            _withdrawBalanceInternal(token0, to, balance0, balance0);
        }
        uint256 balance1 = accountBalances[msg.sender][token1];
        if (balance1 > 0) {
            _withdrawBalanceInternal(token1, to, balance1, balance1);
        }
    }

    function _withdrawBalanceInternal(address token, address to, uint256 balance, uint256 amount) internal {
        require(amount <= balance, "amount>balance");
        accountBalances[msg.sender][token] = accountBalances[msg.sender][token].sub(amount);
        emit BalanceRemoved(msg.sender, token, amount);
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        emit BalanceWithdrawn(msg.sender, token, to, amount);
    }

    function _addToken(uint256 tokenId, address account) internal {

        require(accountTokens[account].length < MAX_POSITIONS_PER_ADDRESS, "max positions reached");

        // get tokens for this nft
        (, , address token0, address token1, , , , , , , , ) = npm.positions(tokenId);

        _checkApprovals(IERC20(token0), IERC20(token1));

        accountTokens[account].push(tokenId);
        ownerOf[tokenId] = account;
    }

    function _checkApprovals(IERC20 token0, IERC20 token1) internal {
        // approve tokens once if not yet approved
        uint256 allowance0 = token0.allowance(address(this), address(npm));
        if (allowance0 == 0) {
            SafeERC20.safeApprove(token0, address(npm), type(uint256).max);
            SafeERC20.safeApprove(token0, address(swapRouter), type(uint256).max);
        }
        uint256 allowance1 = token1.allowance(address(this), address(npm));
        if (allowance1 == 0) {
            SafeERC20.safeApprove(token1, address(npm), type(uint256).max);
            SafeERC20.safeApprove(token1, address(swapRouter), type(uint256).max);
        }
    }

    function _removeToken(address account, uint256 tokenId) internal {
        uint256[] memory accountTokensArr = accountTokens[account];
        uint256 len = accountTokensArr.length;
        uint256 assetIndex = len;

        // limited by MAX_POSITIONS_PER_ADDRESS (no out-of-gas problem)
        for (uint256 i = 0; i < len; i++) {
            if (accountTokensArr[i] == tokenId) {
                assetIndex = i;
                break;
            }
        }

        assert(assetIndex < len);

        uint256[] storage storedList = accountTokens[account];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        delete ownerOf[tokenId];
    }

    function _getTWAPTick(IUniswapV3Pool pool, uint32 twapPeriod) internal view returns (int24, bool) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0; // from (before)
        secondsAgos[1] = twapPeriod; // from (before)
        // pool observe may fail when there is not enough history available
        try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            return (int24((tickCumulatives[0] - tickCumulatives[1]) / twapPeriod), true);
        } catch {
            return (0, false);
        } 
    }

    function _requireMaxTickDifference(int24 tick, int24 other, uint32 maxDifference) internal pure {
        require(other > tick && (uint48(other - tick) < maxDifference) ||
        other <= tick && (uint48(tick - other) < maxDifference),
        "price err");
    }

    // checks oracle for fair price - swaps to position ratio (considering estimated reward) - calculates max amount to be added
    function _swapToPriceRatio(SwapParams memory params) 
        internal 
        returns (uint256 amount0, uint256 amount1, uint256 priceX96, uint256 maxAddAmount0, uint256 maxAddAmount1) 
    {    
        SwapState memory state;

        amount0 = params.amount0;
        amount1 = params.amount1;
        
        // get price
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(params.token0, params.token1, params.fee));
        
        (state.sqrtPriceX96,state.tick,,,,,) = pool.slot0();

        // how many seconds are needed for TWAP protection
        uint32 tSecs = TWAPSeconds;
        if (tSecs > 0) {
            // check that price is not too far from TWAP (protect from price manipulation attacks)
            (state.otherTick, state.twapOk) = _getTWAPTick(pool, tSecs);
            if (state.twapOk) {
                _requireMaxTickDifference(state.tick, state.otherTick, maxTWAPTickDifference);
            } else {
                // if there is no valid TWAP - disable swap
                params.doSwap = false;
            }
        }
        
        priceX96 = uint256(state.sqrtPriceX96).mul(state.sqrtPriceX96).div(Q96);
        state.totalReward0 = amount0.add(amount1.mul(Q96).div(priceX96)).mul(totalRewardX64).div(Q64);

        // swap to correct proportions is requested
        if (params.doSwap) {

            // calculate ideal position amounts
            state.sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(params.tickLower);
            state.sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(params.tickUpper);
            (state.positionAmount0, state.positionAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                                                                state.sqrtPriceX96, 
                                                                state.sqrtPriceX96Lower, 
                                                                state.sqrtPriceX96Upper, 
                                                                Q96); // dummy value we just need ratio

            // calculate how much of the position needs to be converted to the other token
            if (state.positionAmount0 == 0) {
                state.delta0 = amount0;
                state.sell0 = true;
            } else if (state.positionAmount1 == 0) {
                state.delta0 = amount1.mul(Q96).div(priceX96);
                state.sell0 = false;
            } else {
                state.amountRatioX96 = state.positionAmount0.mul(Q96).div(state.positionAmount1);
                state.sell0 = (state.amountRatioX96.mul(amount1) < amount0.mul(Q96));
                if (state.sell0) {
                    state.delta0 = amount0.mul(Q96).sub(state.amountRatioX96.mul(amount1)).div(state.amountRatioX96.mul(priceX96).div(Q96).add(Q96));
                } else {
                    state.delta0 = state.amountRatioX96.mul(amount1).sub(amount0.mul(Q96)).div(state.amountRatioX96.mul(priceX96).div(Q96).add(Q96));
                }
            }

            // adjust delta considering reward payment mode
            if (!params.isOwner) {
                if (params.bc == RewardConversion.TOKEN_0) {
                    state.rewardAmount0 = state.totalReward0;
                    if (state.sell0) {
                        if (state.delta0 >= state.totalReward0) {
                            state.delta0 = state.delta0.sub(state.totalReward0);
                        } else {
                            state.delta0 = state.totalReward0.sub(state.delta0);
                            state.sell0 = false;
                        }
                    } else {
                        state.delta0 = state.delta0.add(state.totalReward0);
                        if (state.delta0 > amount1.mul(Q96).div(priceX96)) {
                            state.delta0 = amount1.mul(Q96).div(priceX96);
                        }
                    }
                } else if (params.bc == RewardConversion.TOKEN_1) {
                    state.rewardAmount1 = state.totalReward0.mul(priceX96).div(Q96);
                    if (!state.sell0) {
                        if (state.delta0 >= state.totalReward0) {
                            state.delta0 = state.delta0.sub(state.totalReward0);
                        } else {
                            state.delta0 = state.totalReward0.sub(state.delta0);
                            state.sell0 = true;
                        }
                    } else {
                        state.delta0 = state.delta0.add(state.totalReward0);
                        if (state.delta0 > amount0) {
                            state.delta0 = amount0;
                        }
                    }
                }
            }

            if (state.delta0 > 0) {
                if (state.sell0) {
                    uint256 amountOut = _swap(
                                            abi.encodePacked(params.token0, params.fee, params.token1), 
                                            state.delta0, 
                                            params.deadline
                                        );
                    amount0 = amount0.sub(state.delta0);
                    amount1 = amount1.add(amountOut);
                } else {
                    state.delta1 = state.delta0.mul(priceX96).div(Q96);
                    // prevent possible rounding to 0 issue
                    if (state.delta1 > 0) {
                        uint256 amountOut = _swap(abi.encodePacked(params.token1, params.fee, params.token0), state.delta1, params.deadline);
                        amount0 = amount0.add(amountOut);
                        amount1 = amount1.sub(state.delta1);
                    }
                }
            }
        } else {
            if (!params.isOwner) {
                if (params.bc == RewardConversion.TOKEN_0) {
                    state.rewardAmount0 = state.totalReward0;
                } else if (params.bc == RewardConversion.TOKEN_1) {
                    state.rewardAmount1 = state.totalReward0.mul(priceX96).div(Q96);
                }
            }
        }
        
        // calculate max amount to add - considering fees (if token owner is calling - no fees)
        if (params.isOwner) {
            maxAddAmount0 = amount0;
            maxAddAmount1 = amount1;
        } else {
            // in case caller is not owner - max amounts to add are slightly lower than available amounts - to account for reward payments
            if (params.bc == RewardConversion.NONE) {
                maxAddAmount0 = amount0.mul(Q64).div(uint(totalRewardX64).add(Q64));
                maxAddAmount1 = amount1.mul(Q64).div(uint(totalRewardX64).add(Q64));
            } else {
                maxAddAmount0 = amount0 > state.rewardAmount0 ? amount0.sub(state.rewardAmount0) : 0;
                maxAddAmount1 = amount1 > state.rewardAmount1 ? amount1.sub(state.rewardAmount1) : 0;
            }
        }
    }

    function _swap(bytes memory swapPath, uint256 amount, uint256 deadline) internal returns (uint256 amountOut) {
        if (amount > 0) {
            amountOut = swapRouter.exactInput(
                ISwapRouter.ExactInputParams(swapPath, address(this), deadline, amount, 0)
            );
        }
    }

    // validate if swap can be done with specified oracle parameters - if not possible reverts
    // if possible returns minAmountOut
    function _validateSwap(bool swap0For1, uint256 amountIn, IUniswapV3Pool pool, uint32 twapPeriod, uint16 maxTickDifference, uint64 maxPriceDifferenceX64) internal view returns (uint256 amountOutMin, int24 currentTick, uint160 sqrtPriceX96, uint256 priceX96) {

        // get current price and tick
        (sqrtPriceX96,currentTick,,,,,) = pool.slot0();

        // check if current tick not too far from TWAP
        if (!_hasMaxTWAPTickDifference(pool, twapPeriod, currentTick, maxTickDifference)) {
            revert('TWAPCheckFailed');
        }

        // calculate min output price price and percentage
        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (swap0For1) {
            amountOutMin = FullMath.mulDiv(amountIn * (Q64 - maxPriceDifferenceX64), priceX96, Q96 * Q64);
        } else {
            amountOutMin = FullMath.mulDiv(amountIn * (Q64 - maxPriceDifferenceX64), Q96, priceX96 * Q64);
        }
    }

    // general swap function which uses external router with off-chain calculated swap instructions
    // does price difference check with amountOutMin param (calculated based on oracle verified price)
    // NOTE: can be only called from (partially) trusted context (nft owner / contract owner / operator) because otherwise swapData can be manipulated to return always amountOutMin
    // returns new token amounts after swap
    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOutMin, bytes memory swapData) internal returns (uint256 amountInDelta, uint256 amountOutDelta) {
        if (amountIn > 0 && swapData.length > 0) {
            uint256 balanceInBefore = tokenIn.balanceOf(address(this));
            uint256 balanceOutBefore = tokenOut.balanceOf(address(this));

            // get router specific swap data
            (address allowanceTarget, bytes memory data) = abi.decode(swapData, (address, bytes));

            // approve needed amount
            SafeERC20.safeApprove(tokenIn, allowanceTarget, amountIn);

            // execute swap with configured router
            (bool success,) = swapRouterReBalance.call(data);
            if (!success) {
                revert('SwapFailed');
            }

            // remove any remaining allowance
            SafeERC20.safeApprove(tokenIn, allowanceTarget, 0);

            uint256 balanceInAfter = tokenIn.balanceOf(address(this));
            uint256 balanceOutAfter = tokenOut.balanceOf(address(this));

            amountInDelta = balanceInBefore - balanceInAfter;
            amountOutDelta = balanceOutAfter - balanceOutBefore;

            // amountMin slippage check
            if (amountOutDelta < amountOutMin) {
                revert('SlippageError');
            }
        }
    }

    // Checks if there was not more tick difference
    // returns false if not enough data available or tick difference >= maxDifference
    function _hasMaxTWAPTickDifference(IUniswapV3Pool pool, uint32 twapPeriod, int24 currentTick, uint16 maxDifference) internal view returns (bool) {
        (int24 twapTick, bool twapOk) = _getTWAPTick(pool, twapPeriod);
        if (twapOk) {
            return twapTick - currentTick >= -int16(maxDifference) && twapTick - currentTick <= int16(maxDifference);
        } else {
            return false;
        }
    }

    // get pool for token
    function _getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
            PoolAddress.computeAddress(
                address(factory),
                PoolAddress.getPoolKey(tokenA, tokenB, fee)
            )
        );
    }

    function _decreaseFullLiquidityAndCollect(uint256 tokenId, uint128 liquidity, uint256 amountRemoveMin0, uint256 amountRemoveMin1, uint256 deadline) internal returns (uint256 amount0, uint256 amount1, uint256 feeAmount0, uint256 feeAmount1) {
        if (liquidity > 0) {
            // store in temporarely "misnamed" variables - see comment below
            (feeAmount0, feeAmount1) = npm.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(
                    tokenId,
                    liquidity,
                    amountRemoveMin0,
                    amountRemoveMin1,
                    deadline
                )
            );
        }
        (amount0, amount1) = npm.collect(
            INonfungiblePositionManager.CollectParams(
                tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );

        // fee amount is what was collected additionally to liquidity amount
        feeAmount0 = amount0 - feeAmount0;
        feeAmount1 = amount1 - feeAmount1;
    }

    // transfers token (or unwraps WETH and sends ETH)
    function _transferToken(address to, IERC20 token, uint256 amount, bool unwrap) internal {
        if (address(weth) == address(token) && unwrap) {
            weth.withdraw(amount);
            (bool sent, ) = to.call{value: amount}("");
            if (!sent) {
                revert('EtherSendFailed');
            }
        } else {
            SafeERC20.safeTransfer(token, to, amount);
        }
    }

    // get tick spacing for fee tier (cached when possible)
    function _getTickSpacing(uint24 fee) internal view returns (int24) {
        if (fee == 10000) {
            return 200;
        } else if (fee == 3000) {
            return 60;
        } else if (fee == 500) {
            return 10;
        } else {
            int24 spacing = factory.feeAmountTickSpacing(fee);
            if (spacing <= 0) {
                revert('NotSupportedFeeTier');
            }
            return spacing;
        }
    }

    // needed for WETH unwrapping
    receive() external payable {
        if (msg.sender != address(weth)) {
            revert('NotWETH');
        }
    }
}