// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

library YieldMath {
    error NotSupportedFeeTier();

    function getTWAPTick(IUniswapV3Pool pool, uint32 twapPeriod) internal view returns (int24, bool) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = twapPeriod;

        try pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            return (int24((tickCumulatives[0] - tickCumulatives[1]) / int56(int32(twapPeriod))), true);
        } catch {
            return (0, false);
        }
    }

    function requireMaxTickDifference(int24 tick, int24 other, uint32 maxDifference) internal pure {
        require(other > tick && (uint48(uint24(other - tick)) < maxDifference) ||
        other <= tick && (uint48(uint24(tick - other)) < maxDifference),
            "price err");
    }

    function hasMaxTWAPTickDifference(IUniswapV3Pool pool, uint32 twapPeriod, int24 currentTick, uint16 maxDifference) internal view returns (bool) {
        (int24 twapTick, bool twapOk) = getTWAPTick(pool, twapPeriod);
        if (twapOk) {
            return twapTick - currentTick >= -int16(maxDifference) && twapTick - currentTick <= int16(maxDifference);
        } else {
            return false;
        }
    }

    function getTickSpacing(address factory, uint24 fee) internal view returns (int24) {
        if (fee == 10000) {
            return 200;
        } else if (fee == 3000) {
            return 60;
        } else if (fee == 500) {
            return 10;
        } else {
            int24 spacing = IUniswapV3Factory(factory).feeAmountTickSpacing(fee);
            if (spacing <= 0) {
                revert NotSupportedFeeTier();
            }
            return spacing;
        }
    }

    function calculatePriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);
    }

    function calculateTotalReward(uint256 amount0, uint256 amount1, uint256 priceX96, uint256 totalRewardX64) internal pure returns (uint256) {
        return amount0 + (amount1 * (1 << 96) / priceX96) * totalRewardX64 / (1 << 64);
    }
}