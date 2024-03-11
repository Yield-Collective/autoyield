// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library YieldMath {
    function calculatePriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);
    }

    function calculateTotalReward(uint256 amount0, uint256 amount1, uint256 priceX96, uint256 totalRewardX64) internal pure returns (uint256) {
        return amount0 + (amount1 * (1 << 96) / priceX96) * totalRewardX64 / (1 << 64);
    }

    function toUint128(uint256 x) internal pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }
}