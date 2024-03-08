// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import {IAutoYield} from "./interfaces/IAutoYield.sol";
import {IMultiYield} from "./interfaces/IMultiYield.sol";

contract MultiYield is IMultiYield {
    IAutoYield public compoundor;

    constructor(IAutoYield compoundor_) {
        compoundor = compoundor_;
    }

    function runConv0Swap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(IAutoYield.AutoCompoundParams(tokenIds[i], IAutoYield.RewardConversion.TOKEN_0, false, true));
        }
    }
    
    function runConv1Swap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(IAutoYield.AutoCompoundParams(tokenIds[i], IAutoYield.RewardConversion.TOKEN_1, false, true));
        }
    }

    function runConv0NoSwap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(IAutoYield.AutoCompoundParams(tokenIds[i], IAutoYield.RewardConversion.TOKEN_0, false, false));
        }
    }
    
    function runConv1NoSwap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(IAutoYield.AutoCompoundParams(tokenIds[i], IAutoYield.RewardConversion.TOKEN_1, false, false));
        }
    }
}