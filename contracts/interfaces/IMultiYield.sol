// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

interface IMultiYield {
    function runConv0Swap(uint256[] calldata tokenIds) external;
    function runConv1Swap(uint256[] calldata tokenIds) external;
    function runConv0NoSwap(uint256[] calldata tokenIds) external;
    function runConv1NoSwap(uint256[] calldata tokenIds) external;
}
