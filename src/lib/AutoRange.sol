// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "v3-core/interfaces/IUniswapV3Factory.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";
import "v3-core/libraries/TickMath.sol";
import "v3-core/libraries/FullMath.sol";

import "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/interfaces/external/IWETH9.sol";

abstract contract AutoRange is Ownable {

    uint256 internal constant Q64 = 2 ** 64;
    uint256 internal constant Q96 = 2 ** 96;

    uint32 public constant MIN_TWAP_SECONDS = 60; // 1 minute
    uint32 public constant MAX_TWAP_TICK_DIFFERENCE = 200; // 2%

    error NotConfigured();
    error NotReady();
    error Unauthorized();
    error InvalidConfig();
    error TWAPCheckFailed();
    error EtherSendFailed();
    error NotWETH();
    error SwapFailed();
    error SlippageError();
    error LiquidityChanged();
    error ExceedsMaxReward();
    error SameRange();
    error NotSupportedFeeTier();
    error SwapAmountTooLarge();

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Factory public immutable factory;
    IWETH9 public immutable weth;

    // preconfigured options for swap routers
    address public immutable swapRouterOption0;
    address public immutable swapRouterOption1;
    address public immutable swapRouterOption2;

    // admin events
    event OperatorChanged(address newOperator, bool active);
    event WithdrawerChanged(address newWithdrawer);
    event TWAPConfigChanged(uint32 TWAPSeconds, uint16 maxTWAPTickDifference);
    event SwapRouterChanged(uint8 swapRouterIndex);
    event RangeChanged(
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId
    );
    event PositionConfigured(
        uint256 indexed tokenId,
        int32 lowerTickLimit,
        int32 upperTickLimit,
        int32 lowerTickDelta,
        int32 upperTickDelta,
        uint64 token0SlippageX64,
        uint64 token1SlippageX64,
        bool onlyFees,
        uint64 maxRewardX64
    );

    // defines when and how a position can be changed by operator
    // when a position is adjusted config for the position is cleared and copied to the newly created position
    struct PositionConfig {
        // needs more than int24 because it can be [-type(uint24).max,type(uint24).max]
        int32 lowerTickLimit; // if negative also in-range positions may be adjusted / if 0 out of range positions may be adjusted
        int32 upperTickLimit; // if negative also in-range positions may be adjusted / if 0 out of range positions may be adjusted
        int32 lowerTickDelta; // this amount is added to current tick (floored to tickspacing) to define lowerTick of new position
        int32 upperTickDelta; // this amount is added to current tick (floored to tickspacing) to define upperTick of new position
        uint64 token0SlippageX64; // max price difference from current pool price for swap / Q64 for token0
        uint64 token1SlippageX64; // max price difference from current pool price for swap / Q64 for token1
        bool onlyFees; // if only fees maybe used for protocol reward
        uint64 maxRewardX64; // max allowed reward percentage of fees or full position
    }

    struct ExecuteParams {
        uint256 tokenId;
        bool swap0To1;
        uint256 amountIn; // if this is set to 0 no swap happens
        bytes swapData;
        uint128 liquidity; // liquidity the calculations are based on
        uint256 amountRemoveMin0; // min amount to be removed from liquidity
        uint256 amountRemoveMin1; // min amount to be removed from liquidity
        uint256 deadline; // for uniswap operations - operator promises fair value
        uint64 rewardX64;  // which reward will be used for protocol, can be max configured amount (considering onlyFees)
    }

    struct ExecuteState {
        address owner;
        address currentOwner;
        IUniswapV3Pool pool;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        int24 currentTick;

        uint256 amount0;
        uint256 amount1;
        uint256 feeAmount0;
        uint256 feeAmount1;

        uint256 maxAddAmount0;
        uint256 maxAddAmount1;

        uint256 amountAdded0;
        uint256 amountAdded1;

        uint128 liquidity;

        uint256 protocolReward0;
        uint256 protocolReward1;
        uint256 amountOutMin;
        uint256 amountInDelta;
        uint256 amountOutDelta;


        uint256 newTokenId;
    }

    // configured tokens
    mapping (uint256 => PositionConfig) public positionConfigs;
    // configurable by owner
    mapping(address => bool) public operators;
    address public withdrawer;
    uint32 public TWAPSeconds;
    uint16 public maxTWAPTickDifference;
    uint8 public swapRouterIndex; // default is 0

    constructor(INonfungiblePositionManager npm, address _operator, address _withdrawer, uint32 _TWAPSeconds, uint16 _maxTWAPTickDifference, address[] memory _swapRouterOptions) {

        nonfungiblePositionManager = npm;
        weth = IWETH9(npm.WETH9());
        factory = IUniswapV3Factory(npm.factory());

        // hardcoded 3 options for swap routers
        swapRouterOption0 = _swapRouterOptions[0];
        swapRouterOption1 = _swapRouterOptions[1];
        swapRouterOption2 = _swapRouterOptions[2];

        emit SwapRouterChanged(0);

        setOperator(_operator, true);
        setWithdrawer(_withdrawer);

        setTWAPConfig(_maxTWAPTickDifference, _TWAPSeconds);
    }

     /**
     * @notice Owner controlled function to change swap router (onlyOwner)
     * @param _swapRouterIndex new swap router index
     */
    function setSwapRouter(uint8 _swapRouterIndex) external onlyOwner {

        // only allow preconfigured routers
        if (_swapRouterIndex > 2) {
            revert InvalidConfig();
        }

        emit SwapRouterChanged(_swapRouterIndex);
        swapRouterIndex = _swapRouterIndex;
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
     * @notice Owner controlled function to increase TWAPSeconds / decrease maxTWAPTickDifference
     */
    function setTWAPConfig(uint16 _maxTWAPTickDifference, uint32 _TWAPSeconds) public onlyOwner {
        if (_TWAPSeconds < MIN_TWAP_SECONDS) {
            revert InvalidConfig();
        }
        if (_maxTWAPTickDifference > MAX_TWAP_TICK_DIFFERENCE) {
            revert InvalidConfig();
        }
        emit TWAPConfigChanged(_TWAPSeconds, _maxTWAPTickDifference);
        TWAPSeconds = _TWAPSeconds;
        maxTWAPTickDifference = _maxTWAPTickDifference;
    }


    /**
     * @notice Withdraws token balance
     * @param tokens Addresses of tokens to withdraw
     * @param to Address to send to
     */
    function withdrawBalances(address[] calldata tokens, address to) external {

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

    /**
     * @notice Withdraws ETH balance
     * @param to Address to send to
     */
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

    /**
     * @notice Adjust token (must be in correct state)
     * Can only be called only from configured operator account
     * Swap needs to be done with max price difference from current pool price - otherwise reverts
     */
    function execute(ExecuteParams calldata params) external {

        if (!operators[msg.sender]) {
            revert Unauthorized();
        }

        ExecuteState memory state;
        PositionConfig memory config = positionConfigs[params.tokenId];

        if (config.lowerTickDelta == config.upperTickDelta) {
            revert NotConfigured();
        }

        if (config.onlyFees && params.rewardX64 > config.maxRewardX64 || !config.onlyFees && params.rewardX64 > config.maxRewardX64) {
            revert ExceedsMaxReward();
        }

        // get position info
        (,, state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, state.liquidity, , , , ) =  nonfungiblePositionManager.positions(params.tokenId);

        if (state.liquidity != params.liquidity) {
            revert LiquidityChanged();
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
            revert SwapAmountTooLarge();
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
                revert SameRange();
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
                    SafeCast.toInt24(baseTick + config.lowerTickDelta), // reverts if out of valid range
                    SafeCast.toInt24(baseTick + config.upperTickDelta), // reverts if out of valid range
                    state.maxAddAmount0,
                    state.maxAddAmount1,
                    0,
                    0,
                    address(this), // is sent to real recipient aftwards
                    params.deadline
                );

            // approve npm
            SafeERC20.safeApprove(IERC20(state.token0), address(nonfungiblePositionManager), state.maxAddAmount0);
            SafeERC20.safeApprove(IERC20(state.token1), address(nonfungiblePositionManager), state.maxAddAmount1);

            // mint is done to address(this) first - its not a safemint
            (state.newTokenId,,state.amountAdded0,state.amountAdded1) = nonfungiblePositionManager.mint(mintParams);

            // remove remaining approval
            SafeERC20.safeApprove(IERC20(state.token0), address(nonfungiblePositionManager), 0);
            SafeERC20.safeApprove(IERC20(state.token1), address(nonfungiblePositionManager), 0);

            state.owner = nonfungiblePositionManager.ownerOf(params.tokenId);

            // send it to current owner
            nonfungiblePositionManager.safeTransferFrom(address(this), state.owner, state.newTokenId);

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
            positionConfigs[state.newTokenId] = config;
            emit PositionConfigured(
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
            delete positionConfigs[params.tokenId];
            emit PositionConfigured(params.tokenId, 0, 0, 0, 0, 0, 0, false, 0);

            emit RangeChanged(params.tokenId, state.newTokenId);

        } else {
            revert NotReady();
        }
    }

    // function to configure a token to be used with this runner
    // it needs to have approvals set for this contract beforehand
    function configToken(uint256 tokenId, PositionConfig calldata config) external {
        address owner = nonfungiblePositionManager.ownerOf(tokenId);
        if (owner != msg.sender) {
            revert Unauthorized();
        }

        // lower tick must be always below or equal to upper tick - if they are equal - range adjustment is deactivated
        if (config.lowerTickDelta > config.upperTickDelta) {
            revert InvalidConfig();
        }

        positionConfigs[tokenId] = config;

        emit PositionConfigured(
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

    // validate if swap can be done with specified oracle parameters - if not possible reverts
    // if possible returns minAmountOut
    function _validateSwap(bool swap0For1, uint256 amountIn, IUniswapV3Pool pool, uint32 twapPeriod, uint16 maxTickDifference, uint64 maxPriceDifferenceX64) internal view returns (uint256 amountOutMin, int24 currentTick, uint160 sqrtPriceX96, uint256 priceX96) {

        // get current price and tick
        (sqrtPriceX96,currentTick,,,,,) = pool.slot0();

        // check if current tick not too far from TWAP
        if (!_hasMaxTWAPTickDifference(pool, twapPeriod, currentTick, maxTickDifference)) {
            revert TWAPCheckFailed();
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
            address swapRouter = swapRouterIndex == 0 ? swapRouterOption0 : (swapRouterIndex == 1 ? swapRouterOption1 : swapRouterOption2);
            (bool success,) = swapRouter.call(data);
            if (!success) {
                revert SwapFailed();
            }

            // remove any remaining allowance
            SafeERC20.safeApprove(tokenIn, allowanceTarget, 0);

            uint256 balanceInAfter = tokenIn.balanceOf(address(this));
            uint256 balanceOutAfter = tokenOut.balanceOf(address(this));

            amountInDelta = balanceInBefore - balanceInAfter;
            amountOutDelta = balanceOutAfter - balanceOutBefore;

            // amountMin slippage check
            if (amountOutDelta < amountOutMin) {
                revert SlippageError();
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

    // gets twap tick from pool history if enough history available
    function _getTWAPTick(IUniswapV3Pool pool, uint32 twapPeriod) internal view returns (int24, bool) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0; // from (before)
        secondsAgos[1] = twapPeriod; // from (before)

        // pool observe may fail when there is not enough history available
        try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            return (int24((tickCumulatives[0] - tickCumulatives[1]) / int56(uint56(twapPeriod))), true);
        } catch {
            return (0, false);
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
            (feeAmount0, feeAmount1) = nonfungiblePositionManager.decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams(
                        tokenId,
                        liquidity,
                        amountRemoveMin0,
                        amountRemoveMin1,
                        deadline
                    )
                );
        }
        (amount0, amount1) = nonfungiblePositionManager.collect(
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
                revert EtherSendFailed();
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
                revert NotSupportedFeeTier();
            }
            return spacing;
        }
    }

    // needed for WETH unwrapping
    receive() external payable {
        if (msg.sender != address(weth)) {
            revert NotWETH();
        }
    }
}