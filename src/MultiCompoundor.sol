// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import {ICompoundor} from "./interfaces/ICompoundor.sol";
import {IMultiCompoundor} from "./interfaces/IMultiCompoundor.sol";

contract MultiCompoundor is IMultiCompoundor {
    ICompoundor public compoundor;

    constructor(ICompoundor compoundor_) {
        compoundor = compoundor_;
    }

    function runConv0Swap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(ICompoundor.AutoCompoundParams(tokenIds[i], ICompoundor.RewardConversion.TOKEN_0, false, true));
        }
    }
    
    function runConv1Swap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(ICompoundor.AutoCompoundParams(tokenIds[i], ICompoundor.RewardConversion.TOKEN_1, false, true));
        }
    }

    function runConv0NoSwap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(ICompoundor.AutoCompoundParams(tokenIds[i], ICompoundor.RewardConversion.TOKEN_0, false, false));
        }
    }
    
    function runConv1NoSwap(uint256[] calldata tokenIds) external override {
        uint256 count = tokenIds.length;
        uint256 i;
        for (; i < count; i++) {
           compoundor.autoCompound(ICompoundor.AutoCompoundParams(tokenIds[i], ICompoundor.RewardConversion.TOKEN_1, false, false));
        }
    }
}