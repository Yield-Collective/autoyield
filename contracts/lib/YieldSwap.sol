// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import "../interfaces/IAutoYield.sol";
import "./YieldMath.sol";

library YieldSwap {
    using SafeMath for uint256;
    uint128 constant public Q96 = 2**96;
    uint128 constant public Q64 = 2**64;
    uint64 constant public MAX_REWARD_X64 = uint64(Q64 / 50);
    uint64 constant public totalRewardX64 = MAX_REWARD_X64;
    uint64 constant public compounderRewardX64 = MAX_REWARD_X64 / 2;
    uint16 constant public maxTWAPTickDifference = 100;
    uint32 constant public TWAPSeconds = 60;

    function calculatePriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);
    }

    function calculateTotalReward(uint256 amount0, uint256 amount1, uint256 priceX96) internal pure returns (uint256) {
        return amount0 + (amount1 * (1 << 96) / priceX96) * totalRewardX64 / (1 << 64);
    }

    function calculateMaxAddAmount(IAutoYield.SwapState memory state, uint256 amount0, uint256 amount1, bool isOwner, IAutoYield.RewardConversion bc) internal pure returns (uint256 maxAddAmount0, uint256 maxAddAmount1) {
        if (isOwner) {
            maxAddAmount0 = amount0;
            maxAddAmount1 = amount1;
        } else {
            if (bc == IAutoYield.RewardConversion.NONE) {
                maxAddAmount0 = amount0.mul(Q64).div(uint(totalRewardX64).add(Q64));
                maxAddAmount1 = amount1.mul(Q64).div(uint(totalRewardX64).add(Q64));
            } else {
                maxAddAmount0 = amount0 > state.rewardAmount0 ? amount0.sub(state.rewardAmount0) : 0;
                maxAddAmount1 = amount1 > state.rewardAmount1 ? amount1.sub(state.rewardAmount1) : 0;
            }
        }
    }

    function calculateSwapState(IAutoYield.SwapState memory state, uint256 priceX96, uint256 amount0, uint256 amount1, bool isOwner, IAutoYield.RewardConversion bc) internal pure returns (IAutoYield.SwapState memory) {
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

        if (!isOwner) {
            if (bc == IAutoYield.RewardConversion.TOKEN_0) {
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
            } else if (bc == IAutoYield.RewardConversion.TOKEN_1) {
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

        return state;
    }

    function validateSwap(bool swap0For1, uint256 amountIn, IUniswapV3Pool pool, uint64 maxPriceDifferenceX64) internal view returns (uint256 amountOutMin, int24 currentTick, uint160 sqrtPriceX96, uint256 priceX96) {
        (sqrtPriceX96,currentTick,,,,,) = pool.slot0();

        if (!YieldMath.hasMaxTWAPTickDifference(pool, TWAPSeconds, currentTick, maxTWAPTickDifference)) {
            revert IAutoYield.TWAPCheckFailed();
        }

        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (swap0For1) {
            amountOutMin = FullMath.mulDiv(amountIn * (Q64 - maxPriceDifferenceX64), priceX96, Q96 * Q64);
        } else {
            amountOutMin = FullMath.mulDiv(amountIn * (Q64 - maxPriceDifferenceX64), Q96, priceX96 * Q64);
        }
    }

    function getPool(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
            PoolAddress.computeAddress(
                factory,
                PoolAddress.getPoolKey(tokenA, tokenB, fee)
            )
        );
    }

    function calculateCompoundFee(IAutoYield.RewardConversion rewardConversion, uint256 amount0, uint256 amount1, uint256 priceX96, uint256 compounded0, uint256 compounded1, bool isNotOwner) internal pure returns (uint256 amount0Fees, uint256 amount1Fees) {
        if (isNotOwner) {
            if (rewardConversion == IAutoYield.RewardConversion.NONE) {
                amount0Fees = compounded0.mul(totalRewardX64).div(Q64);
                amount1Fees = compounded1.mul(totalRewardX64).div(Q64);
            } else {
                uint addedTotal0 = compounded0.add(compounded1.mul(Q96).div(priceX96));
                if (rewardConversion == IAutoYield.RewardConversion.TOKEN_0) {
                    amount0Fees = addedTotal0.mul(totalRewardX64).div(Q64);
                    if (amount0Fees > amount0.sub(compounded0)) {
                        amount0Fees = amount0.sub(compounded0);
                    }
                } else {
                    amount1Fees = addedTotal0.mul(priceX96).div(Q96).mul(totalRewardX64).div(Q64);
                    if (amount1Fees > amount1.sub(compounded1)) {
                        amount1Fees = amount1.sub(compounded1);
                    }
                }
            }
        }
    }

    function decreaseFullLiquidityAndCollect(INonfungiblePositionManager npm, uint256 tokenId, uint128 liquidity, uint256 amountRemoveMin0, uint256 amountRemoveMin1, uint256 deadline) internal returns (uint256 amount0, uint256 amount1, uint256 feeAmount0, uint256 feeAmount1) {
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


    function swapToPriceRatio(IUniswapV3Factory factory, ISwapRouter swapRouter, IAutoYield.SwapParams memory params_)
    internal
    returns (uint256 amount0, uint256 amount1, uint256 priceX96, uint256 maxAddAmount0, uint256 maxAddAmount1)
    {
        IAutoYield.SwapParams memory params = params_;
        IAutoYield.SwapState memory state;

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

        priceX96 = calculatePriceX96(state.sqrtPriceX96);
        state.totalReward0 = calculateTotalReward(amount0, amount1, priceX96);

        if (params.doSwap) {
            state.sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(params.tickLower);
            state.sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(params.tickUpper);
            (state.positionAmount0, state.positionAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                state.sqrtPriceX96,
                state.sqrtPriceX96Lower,
                state.sqrtPriceX96Upper,
                Q96);

            state = calculateSwapState(state, priceX96, amount0, amount1, params.isOwner, params.bc);

            if (state.delta0 > 0) {
                if (state.sell0) {
                    uint256 amountOut = swap(
                        swapRouter,
                        abi.encodePacked(params.token0, params.fee, params.token1),
                        state.delta0,
                        params.deadline
                    );
                    amount0 = amount0.sub(state.delta0);
                    amount1 = amount1.add(amountOut);
                } else {
                    state.delta1 = state.delta0.mul(priceX96).div(Q96);
                    if (state.delta1 > 0) {
                        uint256 amountOut = swap(
                            swapRouter,
                            abi.encodePacked(params.token1, params.fee, params.token0),
                            state.delta1,
                            params.deadline
                        );
                        amount0 = amount0.add(amountOut);
                        amount1 = amount1.sub(state.delta1);
                    }
                }
            }
        } else {
            if (!params.isOwner) {
                if (params.bc == IAutoYield.RewardConversion.TOKEN_0) {
                    state.rewardAmount0 = state.totalReward0;
                } else if (params.bc == IAutoYield.RewardConversion.TOKEN_1) {
                    state.rewardAmount1 = state.totalReward0.mul(priceX96).div(Q96);
                }
            }
        }

        (maxAddAmount0, maxAddAmount1) = calculateMaxAddAmount(state, amount0, amount1, params.isOwner, params.bc);
    }

    function swap(ISwapRouter swapRouter, bytes memory swapPath, uint256 amount, uint256 deadline) internal returns (uint256 amountOut) {
        if (amount > 0) {
            amountOut = swapRouter.exactInput(
                ISwapRouter.ExactInputParams(swapPath, address(this), deadline, amount, 0)
            );
        }
    }

    function safeSwap(address swapRouter, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOutMin, bytes memory swapData) internal returns (uint256 amountInDelta, uint256 amountOutDelta) {
        if (amountIn > 0 && swapData.length > 0) {
            uint256 balanceInBefore = tokenIn.balanceOf(address(this));
            uint256 balanceOutBefore = tokenOut.balanceOf(address(this));

            (address allowanceTarget, bytes memory data) = abi.decode(swapData, (address, bytes));

            SafeERC20.safeApprove(tokenIn, allowanceTarget, amountIn);

            (bool success,) = address(swapRouter).call(data);
            if (!success) {
                revert IAutoYield.SwapFailed();
            }

            SafeERC20.safeApprove(tokenIn, allowanceTarget, 0);

            uint256 balanceInAfter = tokenIn.balanceOf(address(this));
            uint256 balanceOutAfter = tokenOut.balanceOf(address(this));

            amountInDelta = balanceInBefore - balanceInAfter;
            amountOutDelta = balanceOutAfter - balanceOutBefore;

            if (amountOutDelta < amountOutMin) {
                revert IAutoYield.SlippageError();
            }
        }
    }
}