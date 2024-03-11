// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiYield {
    function runConv0Swap(uint256[] calldata tokenIds) external;
    function runConv1Swap(uint256[] calldata tokenIds) external;
    function runConv0NoSwap(uint256[] calldata tokenIds) external;
    function runConv1NoSwap(uint256[] calldata tokenIds) external;
}
