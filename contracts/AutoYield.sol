// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import "./interfaces/IAutoYield.sol";
import "./lib/YieldMath.sol";
import "./lib/YieldBase.sol";

/*
    ___         __    __  ___      __    __
   /   | __  __/ /____\ \/ (_)__  / /___/ /
  / /| |/ / / / __/ __ \  / / _ \/ / __  /
 / ___ / /_/ / /_/ /_/ / / /  __/ / /_/ /
/_/  |_\__,_/\__/\____/_/_/\___/_/\__,_/

*/
contract AutoYield is IAutoYield, YieldBase, ReentrancyGuard, Multicall {
    using SafeMath for uint256;

    uint32 constant public MAX_POSITIONS_PER_ADDRESS = 100;

    IUniswapV3Factory public override factory;
    INonfungiblePositionManager public override npm;
    ISwapRouter public override swapRouter;
    IWETH9 public immutable override weth;
    mapping (uint256 => RangePositionConfig) public rangePositionConfigs;
    mapping(uint256 => address) public override ownerOf;
    mapping(address => uint256[]) public override accountTokens;
    mapping(address => mapping(address => uint256)) public override accountBalances;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, ISwapRouter _swapRouter)
    {
        npm = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
        factory = IUniswapV3Factory(npm.factory());
        weth = IWETH9(npm.WETH9());
        swapRouterReBalance = address(_swapRouter);

        setOperator(msg.sender, true);
        setWithdrawer(msg.sender);

        emit SwapRouterChanged(swapRouterReBalance);
        emit TWAPConfigUpdated(msg.sender, maxTWAPTickDifference, TWAPSeconds);
    }

    function withdrawBalances(address[] calldata tokens, address to) external override {
        if (msg.sender != withdrawer) {
            revert Unauthorized();
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

    function withdrawETH(address to) external {
        if (msg.sender != withdrawer) {
            revert Unauthorized();
        }

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent,) = to.call{value: balance}("");
            if (!sent) {
                revert EtherSendFailed();
            }
        }
    }

    function reBalance(RangeExecuteParams calldata params) external {
        if (!operators[msg.sender]) {
            revert Unauthorized();
        }

        RangeExecuteState memory state;
        RangePositionConfig memory config = rangePositionConfigs[params.tokenId];

        if (config.lowerTickDelta == config.upperTickDelta) {
            revert NotConfigured();
        }

        if (config.onlyFees && params.rewardX64 > config.maxRewardX64 || !config.onlyFees && params.rewardX64 > config.maxRewardX64) {
            revert ExceedsMaxReward();
        }

        (,, state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, state.liquidity, , , , ) =  npm.positions(params.tokenId);

        if (state.liquidity != params.liquidity) {
            revert LiquidityChanged();
        }

        (state.amount0, state.amount1, state.feeAmount0, state.feeAmount1) = _decreaseFullLiquidityAndCollect(params.tokenId, state.liquidity, params.amountRemoveMin0, params.amountRemoveMin1, params.deadline);

        if (config.onlyFees) {
            state.protocolReward0 = state.feeAmount0 * params.rewardX64 / Q64;
            state.protocolReward1 = state.feeAmount1 * params.rewardX64 / Q64;
            state.amount0 -= state.protocolReward0;
            state.amount1 -= state.protocolReward1;
        }

        if (params.swap0To1 && params.amountIn > state.amount0 || !params.swap0To1 && params.amountIn > state.amount1) {
            revert SwapAmountTooLarge();
        }

        state.pool = _getPool(state.token0, state.token1, state.fee);

        (state.amountOutMin,state.currentTick,,) = _validateSwap(params.swap0To1, params.amountIn, state.pool, TWAPSeconds, maxTWAPTickDifference, params.swap0To1 ? config.token0SlippageX64 : config.token1SlippageX64);

        if (state.currentTick < state.tickLower - config.lowerTickLimit || state.currentTick >= state.tickUpper + config.upperTickLimit) {

            int24 tickSpacing = YieldMath.getTickSpacing(factory, state.fee);
            int24 baseTick = state.currentTick - (((state.currentTick % tickSpacing) + tickSpacing) % tickSpacing);

            if (baseTick + config.lowerTickDelta == state.tickLower && baseTick + config.upperTickDelta == state.tickUpper) {
                revert SameRange();
            }

            (state.amountInDelta, state.amountOutDelta) = _swap(params.swap0To1 ? IERC20(state.token0) : IERC20(state.token1), params.swap0To1 ? IERC20(state.token1) : IERC20(state.token0), params.amountIn, state.amountOutMin, params.swapData);

            state.amount0 = params.swap0To1 ? state.amount0 - state.amountInDelta : state.amount0 + state.amountOutDelta;
            state.amount1 = params.swap0To1 ? state.amount1 + state.amountOutDelta : state.amount1 - state.amountInDelta;
            state.maxAddAmount0 = config.onlyFees ? state.amount0 : state.amount0 * Q64 / (params.rewardX64 + Q64);
            state.maxAddAmount1 = config.onlyFees ? state.amount1 : state.amount1 * Q64 / (params.rewardX64 + Q64);

            INonfungiblePositionManager.MintParams memory mintParams =
                                INonfungiblePositionManager.MintParams(
                    address(state.token0),
                    address(state.token1),
                    state.fee,
                    int24(baseTick + config.lowerTickDelta),
                    int24(baseTick + config.upperTickDelta),
                    state.maxAddAmount0,
                    state.maxAddAmount1,
                    0,
                    0,
                    address(this),
                    params.deadline
                );

            SafeERC20.forceApprove(IERC20(state.token0), address(npm), state.maxAddAmount0);
            SafeERC20.forceApprove(IERC20(state.token1), address(npm), state.maxAddAmount1);

            (state.newTokenId,,state.amountAdded0,state.amountAdded1) = npm.mint(mintParams);

            SafeERC20.forceApprove(IERC20(state.token0), address(npm), 0);
            SafeERC20.forceApprove(IERC20(state.token1), address(npm), 0);

            state.owner = npm.ownerOf(params.tokenId);

            npm.safeTransferFrom(address(this), state.owner, state.newTokenId);

            if (!config.onlyFees) {
                state.protocolReward0 = state.amountAdded0 * params.rewardX64 / Q64;
                state.protocolReward1 = state.amountAdded1 * params.rewardX64 / Q64;
                state.amount0 -= state.protocolReward0;
                state.amount1 -= state.protocolReward1;
            }

            if (state.amount0 - state.amountAdded0 > 0) {
                _transferToken(state.owner, IERC20(state.token0), state.amount0 - state.amountAdded0, true);
            }
            if (state.amount1 - state.amountAdded1 > 0) {
                _transferToken(state.owner, IERC20(state.token1), state.amount1 - state.amountAdded1, true);
            }

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

            delete rangePositionConfigs[params.tokenId];
            emit RangePositionConfigured(params.tokenId, 0, 0, 0, 0, 0, 0, false, 0);

            emit RangeChanged(params.tokenId, state.newTokenId);

        } else {
            revert NotReady();
        }
    }

    function configToken(uint256 tokenId, RangePositionConfig calldata config) external {
        address owner = npm.ownerOf(tokenId);
        if (owner != msg.sender) {
            revert Unauthorized();
        }

        if (config.lowerTickDelta > config.upperTickDelta) {
            revert InvalidConfig();
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

    function balanceOf(address account) override external view returns (uint256 balance) {
        return accountTokens[account].length;
    }

    function autoCompound(AutoCompoundParams memory params) 
        override 
        external 
        nonReentrant
        returns (uint256 reward0, uint256 reward1, uint256 compounded0, uint256 compounded1)
    {
        require(ownerOf[params.tokenId] != address(0), "!found");

        AutoCompoundState memory state;
        (state.amount0, state.amount1) = npm.collect(
            INonfungiblePositionManager.CollectParams(params.tokenId, address(this), type(uint128).max, type(uint128).max)
        );
        (, , state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, , , , , ) = 
            npm.positions(params.tokenId);

        state.tokenOwner = ownerOf[params.tokenId];
        state.amount0 = state.amount0.add(accountBalances[state.tokenOwner][state.token0]);
        state.amount1 = state.amount1.add(accountBalances[state.tokenOwner][state.token1]);

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

            (state.amount0, state.amount1, state.priceX96, state.maxAddAmount0, state.maxAddAmount1) = 
                _swapToPriceRatio(swapParams);

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

            if (state.tokenOwner != msg.sender) {
                if (params.rewardConversion == RewardConversion.NONE) {
                    state.amount0Fees = compounded0.mul(totalRewardX64).div(Q64);
                    state.amount1Fees = compounded1.mul(totalRewardX64).div(Q64);
                } else {
                    uint addedTotal0 = compounded0.add(compounded1.mul(Q96).div(state.priceX96));
                    if (params.rewardConversion == RewardConversion.TOKEN_0) {
                        state.amount0Fees = addedTotal0.mul(totalRewardX64).div(Q64);
                        if (state.amount0Fees > state.amount0.sub(compounded0)) {
                            state.amount0Fees = state.amount0.sub(compounded0);
                        }
                    } else {
                        state.amount1Fees = addedTotal0.mul(state.priceX96).div(Q96).mul(totalRewardX64).div(Q64);
                        if (state.amount1Fees > state.amount1.sub(compounded1)) {
                            state.amount1Fees = state.amount1.sub(compounded1);
                        }
                    }
                }
            }

            _setBalance(state.tokenOwner, state.token0, state.amount0.sub(compounded0).sub(state.amount0Fees));
            _setBalance(state.tokenOwner, state.token1, state.amount1.sub(compounded1).sub(state.amount1Fees));

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

    function collect(INonfungiblePositionManager.CollectParams calldata params) 
        override 
        external
        nonReentrant 
        returns (uint256 amount0, uint256 amount1) 
    {
        require(ownerOf[params.tokenId] == msg.sender, "!owner");
        return npm.collect(params);
    }

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

        (, , address token0, address token1, , , , , , , , ) = npm.positions(tokenId);

        _checkApprovals(IERC20(token0), IERC20(token1));

        accountTokens[account].push(tokenId);
        ownerOf[tokenId] = account;
    }

    function _checkApprovals(IERC20 token0, IERC20 token1) internal {
        uint256 allowance0 = token0.allowance(address(this), address(npm));
        if (allowance0 == 0) {
            SafeERC20.forceApprove(token0, address(npm), type(uint256).max);
            SafeERC20.forceApprove(token0, address(swapRouter), type(uint256).max);
        }
        uint256 allowance1 = token1.allowance(address(this), address(npm));
        if (allowance1 == 0) {
            SafeERC20.forceApprove(token1, address(npm), type(uint256).max);
            SafeERC20.forceApprove(token1, address(swapRouter), type(uint256).max);
        }
    }

    function _removeToken(address account, uint256 tokenId) internal {
        uint256[] memory accountTokensArr = accountTokens[account];
        uint256 len = accountTokensArr.length;
        uint256 assetIndex = len;

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

    function _swapToPriceRatio(SwapParams memory params)
        internal
        returns (uint256 amount0, uint256 amount1, uint256 priceX96, uint256 maxAddAmount0, uint256 maxAddAmount1)
    {
        SwapState memory state;

        amount0 = params.amount0;
        amount1 = params.amount1;

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(params.token0, params.token1, params.fee));

        (state.sqrtPriceX96,state.tick,,,,,) = pool.slot0();

        uint32 tSecs = TWAPSeconds;
        if (tSecs > 0) {
            (state.otherTick, state.twapOk) = YieldMath.getTWAPTick(pool, tSecs);
            if (state.twapOk) {
                YieldMath.requireMaxTickDifference(state.tick, state.otherTick, maxTWAPTickDifference);
            } else {
                params.doSwap = false;
            }
        }

        priceX96 = uint256(state.sqrtPriceX96).mul(state.sqrtPriceX96).div(Q96);
        state.totalReward0 = amount0.add(amount1.mul(Q96).div(priceX96)).mul(totalRewardX64).div(Q64);

        if (params.doSwap) {
            state.sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(params.tickLower);
            state.sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(params.tickUpper);
            (state.positionAmount0, state.positionAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                                                                state.sqrtPriceX96,
                                                                state.sqrtPriceX96Lower,
                                                                state.sqrtPriceX96Upper,
                                                                Q96);

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

        if (params.isOwner) {
            maxAddAmount0 = amount0;
            maxAddAmount1 = amount1;
        } else {
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

    function _validateSwap(bool swap0For1, uint256 amountIn, IUniswapV3Pool pool, uint32 twapPeriod, uint16 maxTickDifference, uint64 maxPriceDifferenceX64) internal view returns (uint256 amountOutMin, int24 currentTick, uint160 sqrtPriceX96, uint256 priceX96) {
        (sqrtPriceX96,currentTick,,,,,) = pool.slot0();

        if (!YieldMath.hasMaxTWAPTickDifference(pool, twapPeriod, currentTick, maxTickDifference)) {
            revert TWAPCheckFailed();
        }

        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (swap0For1) {
            amountOutMin = FullMath.mulDiv(amountIn * (Q64 - maxPriceDifferenceX64), priceX96, Q96 * Q64);
        } else {
            amountOutMin = FullMath.mulDiv(amountIn * (Q64 - maxPriceDifferenceX64), Q96, priceX96 * Q64);
        }
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOutMin, bytes memory swapData) internal returns (uint256 amountInDelta, uint256 amountOutDelta) {
        if (amountIn > 0 && swapData.length > 0) {
            uint256 balanceInBefore = tokenIn.balanceOf(address(this));
            uint256 balanceOutBefore = tokenOut.balanceOf(address(this));

            (address allowanceTarget, bytes memory data) = abi.decode(swapData, (address, bytes));

            SafeERC20.forceApprove(tokenIn, allowanceTarget, amountIn);

            (bool success,) = swapRouterReBalance.call(data);
            if (!success) {
                revert SwapFailed();
            }

            SafeERC20.forceApprove(tokenIn, allowanceTarget, 0);

            uint256 balanceInAfter = tokenIn.balanceOf(address(this));
            uint256 balanceOutAfter = tokenOut.balanceOf(address(this));

            amountInDelta = balanceInBefore - balanceInAfter;
            amountOutDelta = balanceOutAfter - balanceOutBefore;

            if (amountOutDelta < amountOutMin) {
                revert SlippageError();
            }
        }
    }

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

        feeAmount0 = amount0 - feeAmount0;
        feeAmount1 = amount1 - feeAmount1;
    }

    function _transferToken(address to, IERC20 token, uint256 amount, bool unwrap) internal {
        if (address(weth) == address(token) && unwrap) {
            weth.withdraw(amount);
            (bool sent, ) = to.call{value: amount}("");
            if (!sent) {
                revert EtherSendFailed();
            }
        } else {
            SafeERC20.safeTransfer(token, to, amount);
        }
    }

    receive() external payable {
        if (msg.sender != address(weth)) {
            revert NotWETH();
        }
    }
}