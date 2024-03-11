// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IUniswapV3Immutables.sol";

abstract contract UniswapV3Immutables is IUniswapV3Immutables {
    INonfungiblePositionManager public immutable npm;
    IUniswapV3Factory public immutable factory;
    IWETH9 public immutable weth;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager) {
        npm = _nonfungiblePositionManager;
        factory = IUniswapV3Factory(npm.factory());
        weth = IWETH9(npm.WETH9());
    }
}
