// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/src/utils/SafeTransferLib.sol";
import "solady/src/utils/FixedPointMathLib.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "../interfaces/IYieldSwapper.sol";
import "../lib/YieldMath.sol";

abstract contract YieldSwapper is IYieldSwapper {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint160;
    using SafeTransferLib for address;

    uint128 constant public Q96 = 2**96;
    uint128 constant public Q64 = 2**64;
    uint64 constant public MAX_REWARD_X64 = uint64(Q64 / 50);
    uint64 constant public totalRewardX64 = MAX_REWARD_X64;
    uint16 constant public maxTWAPTickDifference = 100;
    uint32 constant public TWAPSeconds = 60;

    address public operator;

    ISwapRouter public swapRouter;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
        operator = msg.sender;
    }

    function _validateSwap(bool swap0For1, uint256 amountIn, IUniswapV3Pool pool, uint64 maxPriceDifferenceX64) internal view returns (uint256 amountOutMin, int24 currentTick, uint160 sqrtPriceX96, uint256 priceX96) {
        (sqrtPriceX96,currentTick,,,,,) = pool.slot0();

        if (!_hasMaxTWAPTickDifference(pool, TWAPSeconds, currentTick, maxTWAPTickDifference)) {
            revert TWAPCheckFailed();
        }

        priceX96 = sqrtPriceX96.fullMulDiv(sqrtPriceX96, Q96);
        if (swap0For1) {
            amountOutMin = (amountIn * (Q64 - maxPriceDifferenceX64)).fullMulDiv(priceX96, Q96 * Q64);
        } else {
            amountOutMin = (amountIn * (Q64 - maxPriceDifferenceX64)).fullMulDiv(Q96, priceX96 * Q64);
        }
    }

    function _calculateCompoundFee(RewardConversion rewardConversion, uint256 amount0, uint256 amount1, uint256 priceX96, uint256 compounded0, uint256 compounded1, bool isNotOwner) internal pure returns (uint256 amount0Fees, uint256 amount1Fees) {
        if (isNotOwner) {
            if (rewardConversion == RewardConversion.NONE) {
                amount0Fees = compounded0.rawMul(totalRewardX64).rawDiv(Q64);
                amount1Fees = compounded1.rawMul(totalRewardX64).rawDiv(Q64);
            } else {
                uint addedTotal0 = compounded0.rawAdd(compounded1.rawMul(Q96).rawDiv(priceX96));
                if (rewardConversion == RewardConversion.TOKEN_0) {
                    amount0Fees = addedTotal0.rawMul(totalRewardX64).rawDiv(Q64);
                    if (amount0Fees > amount0.rawSub(compounded0)) {
                        amount0Fees = amount0.rawSub(compounded0);
                    }
                } else {
                    amount1Fees = addedTotal0.rawMul(priceX96).rawDiv(Q96).rawMul(totalRewardX64).rawDiv(Q64);
                    if (amount1Fees > amount1.rawSub(compounded1)) {
                        amount1Fees = amount1.rawSub(compounded1);
                    }
                }
            }
        }
    }

    function _decreaseFullLiquidityAndCollect(INonfungiblePositionManager npm, uint256 tokenId, uint128 liquidity, uint256 amountRemoveMin0, uint256 amountRemoveMin1, uint256 deadline) internal returns (uint256 amount0, uint256 amount1, uint256 feeAmount0, uint256 feeAmount1) {
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


    function _swapToPriceRatio(IUniswapV3Factory factory, SwapParams memory params_)
    internal
    returns (uint256 amount0, uint256 amount1, uint256 priceX96, uint256 maxAddAmount0, uint256 maxAddAmount1)
    {
        SwapParams memory params = params_;
        SwapState memory state;

        amount0 = params.amount0;
        amount1 = params.amount1;

        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(params.token0, params.token1, params.fee));

        (state.sqrtPriceX96,state.tick,,,,,) = pool.slot0();

        uint32 tSecs = TWAPSeconds;
        if (tSecs > 0) {
            (state.otherTick, state.twapOk) = _getTWAPTick(pool, tSecs);
            if (state.twapOk) {
                _requireMaxTickDifference(state.tick, state.otherTick, maxTWAPTickDifference);
            } else {
                params.doSwap = false;
            }
        }

        priceX96 = YieldMath.calculatePriceX96(state.sqrtPriceX96);
        state.totalReward0 = YieldMath.calculateTotalReward(amount0, amount1, priceX96, totalRewardX64);

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
                state.delta0 = amount1.rawMul(Q96).rawDiv(priceX96);
                state.sell0 = false;
            } else {
                state.amountRatioX96 = state.positionAmount0.rawMul(Q96).rawDiv(state.positionAmount1);
                state.sell0 = (state.amountRatioX96.rawMul(amount1) < amount0.rawMul(Q96));
                if (state.sell0) {
                    state.delta0 = amount0.rawMul(Q96).rawSub(state.amountRatioX96.rawMul(amount1)).rawDiv(state.amountRatioX96.rawMul(priceX96).rawDiv(Q96).rawAdd(Q96));
                } else {
                    state.delta0 = state.amountRatioX96.rawMul(amount1).rawSub(amount0.rawMul(Q96)).rawDiv(state.amountRatioX96.rawMul(priceX96).rawDiv(Q96).rawAdd(Q96));
                }
            }

            if (!params.isOwner) {
                if (params.bc == RewardConversion.TOKEN_0) {
                    state.rewardAmount0 = state.totalReward0;
                    if (state.sell0) {
                        if (state.delta0 >= state.totalReward0) {
                            state.delta0 = state.delta0.rawSub(state.totalReward0);
                        } else {
                            state.delta0 = state.totalReward0.rawSub(state.delta0);
                            state.sell0 = false;
                        }
                    } else {
                        state.delta0 = state.delta0.rawAdd(state.totalReward0);
                        if (state.delta0 > amount1.rawMul(Q96).rawDiv(priceX96)) {
                            state.delta0 = amount1.rawMul(Q96).rawDiv(priceX96);
                        }
                    }
                } else if (params.bc == RewardConversion.TOKEN_1) {
                    state.rewardAmount1 = state.totalReward0.rawMul(priceX96).rawDiv(Q96);
                    if (!state.sell0) {
                        if (state.delta0 >= state.totalReward0) {
                            state.delta0 = state.delta0.rawSub(state.totalReward0);
                        } else {
                            state.delta0 = state.totalReward0.rawSub(state.delta0);
                            state.sell0 = true;
                        }
                    } else {
                        state.delta0 = state.delta0.rawAdd(state.totalReward0);
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
                    amount0 = amount0.rawSub(state.delta0);
                    amount1 = amount1.rawAdd(amountOut);
                } else {
                    state.delta1 = state.delta0.rawMul(priceX96).rawDiv(Q96);
                    if (state.delta1 > 0) {
                        uint256 amountOut = _swap(
                            abi.encodePacked(params.token1, params.fee, params.token0),
                            state.delta1,
                            params.deadline
                        );
                        amount0 = amount0.rawAdd(amountOut);
                        amount1 = amount1.rawSub(state.delta1);
                    }
                }
            }
        } else {
            if (!params.isOwner) {
                if (params.bc == RewardConversion.TOKEN_0) {
                    state.rewardAmount0 = state.totalReward0;
                } else if (params.bc == RewardConversion.TOKEN_1) {
                    state.rewardAmount1 = state.totalReward0.rawMul(priceX96).rawDiv(Q96);
                }
            }
        }

        if (params.isOwner) {
            maxAddAmount0 = amount0;
            maxAddAmount1 = amount1;
        } else {
            if (params.bc == RewardConversion.NONE) {
                maxAddAmount0 = amount0.rawMul(Q64).rawDiv(uint(totalRewardX64).rawAdd(Q64));
                maxAddAmount1 = amount1.rawMul(Q64).rawDiv(uint(totalRewardX64).rawAdd(Q64));
            } else {
                maxAddAmount0 = amount0 > state.rewardAmount0 ? amount0.rawSub(state.rewardAmount0) : 0;
                maxAddAmount1 = amount1 > state.rewardAmount1 ? amount1.rawSub(state.rewardAmount1) : 0;
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

    function _safeSwap(address swapRouter_, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, bytes memory swapData) internal returns (uint256 amountInDelta, uint256 amountOutDelta) {
        if (amountIn > 0 && swapData.length > 0) {
            uint256 balanceInBefore = tokenIn.balanceOf(address(this));
            uint256 balanceOutBefore = tokenOut.balanceOf(address(this));

            (address allowanceTarget, bytes memory data) = abi.decode(swapData, (address, bytes));

            tokenIn.safeApprove(allowanceTarget, amountIn);

            (bool success,) = address(swapRouter_).call(data);
            if (!success) {
                revert SwapFailed();
            }

            tokenIn.safeApprove(allowanceTarget, 0);

            uint256 balanceInAfter = tokenIn.balanceOf(address(this));
            uint256 balanceOutAfter = tokenOut.balanceOf(address(this));

            amountInDelta = balanceInBefore - balanceInAfter;
            amountOutDelta = balanceOutAfter - balanceOutBefore;

            if (amountOutDelta < amountOutMin) {
                revert SlippageError();
            }
        }
    }

    function _getTWAPTick(IUniswapV3Pool pool, uint32 twapPeriod) internal view returns (int24, bool) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = twapPeriod;

        try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            return (int24((tickCumulatives[0] - tickCumulatives[1]) / int56(int32(twapPeriod))), true);
        } catch {
            return (0, false);
        }
    }

    function _requireMaxTickDifference(int24 tick, int24 other, uint32 maxDifference) internal pure {
        require(other > tick && (uint48(uint24(other - tick)) < maxDifference) ||
        other <= tick && (uint48(uint24(tick - other)) < maxDifference),
            "price err");
    }

    function _hasMaxTWAPTickDifference(IUniswapV3Pool pool, uint32 twapPeriod, int24 currentTick, uint16 maxDifference) internal view returns (bool) {
        (int24 twapTick, bool twapOk) = _getTWAPTick(pool, twapPeriod);
        if (twapOk) {
            return twapTick - currentTick >= -int16(maxDifference) && twapTick - currentTick <= int16(maxDifference);
        } else {
            return false;
        }
    }
}