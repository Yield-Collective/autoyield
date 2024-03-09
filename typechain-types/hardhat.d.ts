/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { ethers } from "ethers";
import {
  DeployContractOptions,
  FactoryOptions,
  HardhatEthersHelpers as HardhatEthersHelpersBase,
} from "@nomicfoundation/hardhat-ethers/types";

import * as Contracts from ".";

declare module "hardhat/types/runtime" {
  interface HardhatEthersHelpers extends HardhatEthersHelpersBase {
    getContractFactory(
      name: "Ownable",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.Ownable__factory>;
    getContractFactory(
      name: "IERC20Permit",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC20Permit__factory>;
    getContractFactory(
      name: "IERC20",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC20__factory>;
    getContractFactory(
      name: "IERC721Enumerable",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC721Enumerable__factory>;
    getContractFactory(
      name: "IERC721Metadata",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC721Metadata__factory>;
    getContractFactory(
      name: "IERC721",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC721__factory>;
    getContractFactory(
      name: "IERC721Receiver",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC721Receiver__factory>;
    getContractFactory(
      name: "IERC165",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC165__factory>;
    getContractFactory(
      name: "Multicall",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.Multicall__factory>;
    getContractFactory(
      name: "IV3SwapRouter",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IV3SwapRouter__factory>;
    getContractFactory(
      name: "IUniswapV3SwapCallback",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3SwapCallback__factory>;
    getContractFactory(
      name: "IUniswapV3Factory",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3Factory__factory>;
    getContractFactory(
      name: "IUniswapV3Pool",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3Pool__factory>;
    getContractFactory(
      name: "IUniswapV3PoolActions",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3PoolActions__factory>;
    getContractFactory(
      name: "IUniswapV3PoolDerivedState",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3PoolDerivedState__factory>;
    getContractFactory(
      name: "IUniswapV3PoolEvents",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3PoolEvents__factory>;
    getContractFactory(
      name: "IUniswapV3PoolImmutables",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3PoolImmutables__factory>;
    getContractFactory(
      name: "IUniswapV3PoolOwnerActions",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3PoolOwnerActions__factory>;
    getContractFactory(
      name: "IUniswapV3PoolState",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IUniswapV3PoolState__factory>;
    getContractFactory(
      name: "IWETH9",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IWETH9__factory>;
    getContractFactory(
      name: "IERC721Permit",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IERC721Permit__factory>;
    getContractFactory(
      name: "INonfungiblePositionManager",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.INonfungiblePositionManager__factory>;
    getContractFactory(
      name: "IPeripheryImmutableState",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IPeripheryImmutableState__factory>;
    getContractFactory(
      name: "IPeripheryPayments",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IPeripheryPayments__factory>;
    getContractFactory(
      name: "IPoolInitializer",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IPoolInitializer__factory>;
    getContractFactory(
      name: "ISwapRouter",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.ISwapRouter__factory>;
    getContractFactory(
      name: "AutoYield",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.AutoYield__factory>;
    getContractFactory(
      name: "AutoExit",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.AutoExit__factory>;
    getContractFactory(
      name: "Automator",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.Automator__factory>;
    getContractFactory(
      name: "AutoRange",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.AutoRange__factory>;
    getContractFactory(
      name: "IAutoYield",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IAutoYield__factory>;
    getContractFactory(
      name: "IMultiYield",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.IMultiYield__factory>;
    getContractFactory(
      name: "YieldBase",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.YieldBase__factory>;
    getContractFactory(
      name: "YieldMath",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.YieldMath__factory>;
    getContractFactory(
      name: "YieldSetter",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.YieldSetter__factory>;
    getContractFactory(
      name: "MultiYield",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.MultiYield__factory>;
    getContractFactory(
      name: "SelfYield",
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<Contracts.SelfYield__factory>;

    getContractAt(
      name: "Ownable",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.Ownable>;
    getContractAt(
      name: "IERC20Permit",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC20Permit>;
    getContractAt(
      name: "IERC20",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC20>;
    getContractAt(
      name: "IERC721Enumerable",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC721Enumerable>;
    getContractAt(
      name: "IERC721Metadata",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC721Metadata>;
    getContractAt(
      name: "IERC721",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC721>;
    getContractAt(
      name: "IERC721Receiver",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC721Receiver>;
    getContractAt(
      name: "IERC165",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC165>;
    getContractAt(
      name: "Multicall",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.Multicall>;
    getContractAt(
      name: "IV3SwapRouter",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IV3SwapRouter>;
    getContractAt(
      name: "IUniswapV3SwapCallback",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3SwapCallback>;
    getContractAt(
      name: "IUniswapV3Factory",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3Factory>;
    getContractAt(
      name: "IUniswapV3Pool",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3Pool>;
    getContractAt(
      name: "IUniswapV3PoolActions",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3PoolActions>;
    getContractAt(
      name: "IUniswapV3PoolDerivedState",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3PoolDerivedState>;
    getContractAt(
      name: "IUniswapV3PoolEvents",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3PoolEvents>;
    getContractAt(
      name: "IUniswapV3PoolImmutables",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3PoolImmutables>;
    getContractAt(
      name: "IUniswapV3PoolOwnerActions",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3PoolOwnerActions>;
    getContractAt(
      name: "IUniswapV3PoolState",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IUniswapV3PoolState>;
    getContractAt(
      name: "IWETH9",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IWETH9>;
    getContractAt(
      name: "IERC721Permit",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IERC721Permit>;
    getContractAt(
      name: "INonfungiblePositionManager",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.INonfungiblePositionManager>;
    getContractAt(
      name: "IPeripheryImmutableState",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IPeripheryImmutableState>;
    getContractAt(
      name: "IPeripheryPayments",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IPeripheryPayments>;
    getContractAt(
      name: "IPoolInitializer",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IPoolInitializer>;
    getContractAt(
      name: "ISwapRouter",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.ISwapRouter>;
    getContractAt(
      name: "AutoYield",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.AutoYield>;
    getContractAt(
      name: "AutoExit",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.AutoExit>;
    getContractAt(
      name: "Automator",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.Automator>;
    getContractAt(
      name: "AutoRange",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.AutoRange>;
    getContractAt(
      name: "IAutoYield",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IAutoYield>;
    getContractAt(
      name: "IMultiYield",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.IMultiYield>;
    getContractAt(
      name: "YieldBase",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.YieldBase>;
    getContractAt(
      name: "YieldMath",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.YieldMath>;
    getContractAt(
      name: "YieldSetter",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.YieldSetter>;
    getContractAt(
      name: "MultiYield",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.MultiYield>;
    getContractAt(
      name: "SelfYield",
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<Contracts.SelfYield>;

    deployContract(
      name: "Ownable",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.Ownable>;
    deployContract(
      name: "IERC20Permit",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC20Permit>;
    deployContract(
      name: "IERC20",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC20>;
    deployContract(
      name: "IERC721Enumerable",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Enumerable>;
    deployContract(
      name: "IERC721Metadata",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Metadata>;
    deployContract(
      name: "IERC721",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721>;
    deployContract(
      name: "IERC721Receiver",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Receiver>;
    deployContract(
      name: "IERC165",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC165>;
    deployContract(
      name: "Multicall",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.Multicall>;
    deployContract(
      name: "IV3SwapRouter",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IV3SwapRouter>;
    deployContract(
      name: "IUniswapV3SwapCallback",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3SwapCallback>;
    deployContract(
      name: "IUniswapV3Factory",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3Factory>;
    deployContract(
      name: "IUniswapV3Pool",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3Pool>;
    deployContract(
      name: "IUniswapV3PoolActions",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolActions>;
    deployContract(
      name: "IUniswapV3PoolDerivedState",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolDerivedState>;
    deployContract(
      name: "IUniswapV3PoolEvents",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolEvents>;
    deployContract(
      name: "IUniswapV3PoolImmutables",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolImmutables>;
    deployContract(
      name: "IUniswapV3PoolOwnerActions",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolOwnerActions>;
    deployContract(
      name: "IUniswapV3PoolState",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolState>;
    deployContract(
      name: "IWETH9",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IWETH9>;
    deployContract(
      name: "IERC721Permit",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Permit>;
    deployContract(
      name: "INonfungiblePositionManager",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.INonfungiblePositionManager>;
    deployContract(
      name: "IPeripheryImmutableState",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IPeripheryImmutableState>;
    deployContract(
      name: "IPeripheryPayments",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IPeripheryPayments>;
    deployContract(
      name: "IPoolInitializer",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IPoolInitializer>;
    deployContract(
      name: "ISwapRouter",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.ISwapRouter>;
    deployContract(
      name: "AutoYield",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.AutoYield>;
    deployContract(
      name: "AutoExit",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.AutoExit>;
    deployContract(
      name: "Automator",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.Automator>;
    deployContract(
      name: "AutoRange",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.AutoRange>;
    deployContract(
      name: "IAutoYield",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IAutoYield>;
    deployContract(
      name: "IMultiYield",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IMultiYield>;
    deployContract(
      name: "YieldBase",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.YieldBase>;
    deployContract(
      name: "YieldMath",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.YieldMath>;
    deployContract(
      name: "YieldSetter",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.YieldSetter>;
    deployContract(
      name: "MultiYield",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.MultiYield>;
    deployContract(
      name: "SelfYield",
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.SelfYield>;

    deployContract(
      name: "Ownable",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.Ownable>;
    deployContract(
      name: "IERC20Permit",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC20Permit>;
    deployContract(
      name: "IERC20",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC20>;
    deployContract(
      name: "IERC721Enumerable",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Enumerable>;
    deployContract(
      name: "IERC721Metadata",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Metadata>;
    deployContract(
      name: "IERC721",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721>;
    deployContract(
      name: "IERC721Receiver",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Receiver>;
    deployContract(
      name: "IERC165",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC165>;
    deployContract(
      name: "Multicall",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.Multicall>;
    deployContract(
      name: "IV3SwapRouter",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IV3SwapRouter>;
    deployContract(
      name: "IUniswapV3SwapCallback",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3SwapCallback>;
    deployContract(
      name: "IUniswapV3Factory",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3Factory>;
    deployContract(
      name: "IUniswapV3Pool",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3Pool>;
    deployContract(
      name: "IUniswapV3PoolActions",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolActions>;
    deployContract(
      name: "IUniswapV3PoolDerivedState",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolDerivedState>;
    deployContract(
      name: "IUniswapV3PoolEvents",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolEvents>;
    deployContract(
      name: "IUniswapV3PoolImmutables",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolImmutables>;
    deployContract(
      name: "IUniswapV3PoolOwnerActions",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolOwnerActions>;
    deployContract(
      name: "IUniswapV3PoolState",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IUniswapV3PoolState>;
    deployContract(
      name: "IWETH9",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IWETH9>;
    deployContract(
      name: "IERC721Permit",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IERC721Permit>;
    deployContract(
      name: "INonfungiblePositionManager",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.INonfungiblePositionManager>;
    deployContract(
      name: "IPeripheryImmutableState",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IPeripheryImmutableState>;
    deployContract(
      name: "IPeripheryPayments",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IPeripheryPayments>;
    deployContract(
      name: "IPoolInitializer",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IPoolInitializer>;
    deployContract(
      name: "ISwapRouter",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.ISwapRouter>;
    deployContract(
      name: "AutoYield",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.AutoYield>;
    deployContract(
      name: "AutoExit",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.AutoExit>;
    deployContract(
      name: "Automator",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.Automator>;
    deployContract(
      name: "AutoRange",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.AutoRange>;
    deployContract(
      name: "IAutoYield",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IAutoYield>;
    deployContract(
      name: "IMultiYield",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.IMultiYield>;
    deployContract(
      name: "YieldBase",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.YieldBase>;
    deployContract(
      name: "YieldMath",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.YieldMath>;
    deployContract(
      name: "YieldSetter",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.YieldSetter>;
    deployContract(
      name: "MultiYield",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.MultiYield>;
    deployContract(
      name: "SelfYield",
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<Contracts.SelfYield>;

    // default types
    getContractFactory(
      name: string,
      signerOrOptions?: ethers.Signer | FactoryOptions
    ): Promise<ethers.ContractFactory>;
    getContractFactory(
      abi: any[],
      bytecode: ethers.BytesLike,
      signer?: ethers.Signer
    ): Promise<ethers.ContractFactory>;
    getContractAt(
      nameOrAbi: string | any[],
      address: string | ethers.Addressable,
      signer?: ethers.Signer
    ): Promise<ethers.Contract>;
    deployContract(
      name: string,
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<ethers.Contract>;
    deployContract(
      name: string,
      args: any[],
      signerOrOptions?: ethers.Signer | DeployContractOptions
    ): Promise<ethers.Contract>;
  }
}
