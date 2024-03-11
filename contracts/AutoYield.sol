// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "./base/YieldSwapper.sol";
import "./base/UniswapV3Immutables.sol";
import "./interfaces/IAutoYield.sol";

/*
    ___         __    __  ___      __    __
   /   | __  __/ /____\ \/ (_)__  / /___/ /
  / /| |/ / / / __/ __ \  / / _ \/ / __  /
 / ___ / /_/ / /_/ /_/ / / /  __/ / /_/ /
/_/  |_\__,_/\__/\____/_/_/\___/_/\__,_/

*/
contract AutoYield is IAutoYield, YieldSwapper, UniswapV3Immutables, ReentrancyGuard, Multicall {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    uint64 constant public compounderRewardX64 = MAX_REWARD_X64 / 2;

    mapping(uint256 => RangePositionConfig) public rangePositionConfigs;
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256[]) public accountTokens;
    mapping(address => mapping(address => uint256)) public accountBalances;

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISwapRouter _swapRouter
    )
    UniswapV3Immutables(_nonfungiblePositionManager)
    YieldSwapper(_swapRouter)
    {}

    function autoCompound(
        AutoCompoundParams memory params
    )
    external
    nonReentrant
    returns (
        uint256 reward0,
        uint256 reward1,
        uint256 compounded0,
        uint256 compounded1
    )
    {
        require(ownerOf[params.tokenId] != address(0));

        AutoCompoundState memory state;
        (state.amount0, state.amount1) = npm.collect(
            INonfungiblePositionManager.CollectParams(
                params.tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            )
        );
        (
        ,
        ,
            state.token0,
            state.token1,
            state.fee,
            state.tickLower,
            state.tickUpper,
        ,
        ,
        ,
        ,

        ) = npm.positions(params.tokenId);

        state.tokenOwner = ownerOf[params.tokenId];
        state.amount0 = state.amount0.rawAdd(
            accountBalances[state.tokenOwner][state.token0]
        );
        state.amount1 = state.amount1.rawAdd(
            accountBalances[state.tokenOwner][state.token1]
        );

        if (state.amount0 > 0 || state.amount1 > 0) {
            SwapParams memory swapParams = SwapParams(
                state.token0,
                state.token1,
                state.fee,
                state.tickLower,
                state.tickUpper,
                state.amount0,
                state.amount1,
                block.timestamp,
                params.rewardConversion,
                state.tokenOwner == msg.sender,
                params.doSwap
            );

            (
                state.amount0,
                state.amount1,
                state.priceX96,
                state.maxAddAmount0,
                state.maxAddAmount1
            ) = _swapToPriceRatio(factory, swapParams);

            if (state.maxAddAmount0 > 0 || state.maxAddAmount1 > 0) {
                (, compounded0, compounded1) = npm.increaseLiquidity(
                    INonfungiblePositionManager.IncreaseLiquidityParams(
                        params.tokenId,
                        state.maxAddAmount0,
                        state.maxAddAmount1,
                        0,
                        0,
                        block.timestamp
                    )
                );
            }

            bool isNotOwner = state.tokenOwner != msg.sender;
            uint256 amount0Fees;
            uint256 amount1Fees;

            if (isNotOwner) {
                if (params.rewardConversion == RewardConversion.NONE) {
                    amount0Fees = compounded0.rawMul(totalRewardX64).rawDiv(Q64);
                    amount1Fees = compounded1.rawMul(totalRewardX64).rawDiv(Q64);
                } else {
                    uint addedTotal0 = compounded0.rawAdd(compounded1.rawMul(Q96).rawDiv(state.priceX96));
                    if (params.rewardConversion == RewardConversion.TOKEN_0) {
                        amount0Fees = addedTotal0.rawMul(totalRewardX64).rawDiv(Q64);
                        if (amount0Fees > state.amount0.rawSub(compounded0)) {
                            amount0Fees = state.amount0.rawSub(compounded0);
                        }
                    } else {
                        amount1Fees = addedTotal0.rawMul(state.priceX96).rawDiv(Q96).rawMul(totalRewardX64).rawDiv(Q64);
                        if (amount1Fees > state.amount1.rawSub(compounded1)) {
                            amount1Fees = state.amount1.rawSub(compounded1);
                        }
                    }
                }
            }

            _setBalance(
                state.tokenOwner,
                state.token0,
                state.amount0.rawSub(compounded0).rawSub(amount0Fees)
            );
            _setBalance(
                state.tokenOwner,
                state.token1,
                state.amount1.rawSub(compounded1).rawSub(amount1Fees)
            );

            if (isNotOwner) {
                uint64 protocolRewardX64 = totalRewardX64 -
                            compounderRewardX64;
                uint256 protocolFees0 = amount0Fees.rawMul(protocolRewardX64).rawDiv(
                    totalRewardX64
                );
                uint256 protocolFees1 = amount1Fees.rawMul(protocolRewardX64).rawDiv(
                    totalRewardX64
                );

                reward0 = amount0Fees.rawSub(protocolFees0);
                reward1 = amount1Fees.rawSub(protocolFees1);

                _increaseBalance(msg.sender, state.token0, reward0);
                _increaseBalance(msg.sender, state.token1, reward1);
                _increaseBalance(operator, state.token0, protocolFees0);
                _increaseBalance(operator, state.token1, protocolFees1);
            }
        }

        if (params.withdrawReward) {
            _withdrawFullBalances(state.token0, state.token1, msg.sender);
        }

        emit AutoCompounded(
            msg.sender,
            params.tokenId,
            compounded0,
            compounded1,
            reward0,
            reward1,
            state.token0,
            state.token1
        );
    }

    function autoRange(RangeExecuteParams calldata params) external {
        if (msg.sender != operator) {
            revert Unauthorized();
        }

        RangeExecuteState memory state;
        RangePositionConfig memory config = rangePositionConfigs[
                        params.tokenId
            ];

        if (config.lowerTickDelta == config.upperTickDelta) {
            revert NotConfigured();
        }

        if (
            (config.onlyFees && params.rewardX64 > config.maxRewardX64) ||
            (!config.onlyFees && params.rewardX64 > config.maxRewardX64)
        ) {
            revert ExceedsMaxReward();
        }

        (
        ,
        ,
            state.token0,
            state.token1,
            state.fee,
            state.tickLower,
            state.tickUpper,
            state.liquidity,
        ,
        ,
        ,

        ) = npm.positions(params.tokenId);

        if (state.liquidity != params.liquidity) {
            revert LiquidityChanged();
        }

        (
            state.amount0,
            state.amount1,
            state.feeAmount0,
            state.feeAmount1
        ) = _decreaseFullLiquidityAndCollect(
            npm,
            params.tokenId,
            state.liquidity,
            params.amountRemoveMin0,
            params.amountRemoveMin1,
            params.deadline
        );

        if (config.onlyFees) {
            state.protocolReward0 =
                (state.feeAmount0 * params.rewardX64) /
                Q64;
            state.protocolReward1 =
                (state.feeAmount1 * params.rewardX64) /
                Q64;
            state.amount0 -= state.protocolReward0;
            state.amount1 -= state.protocolReward1;
        }

        if (
            (params.swap0To1 && params.amountIn > state.amount0) ||
            (!params.swap0To1 && params.amountIn > state.amount1)
        ) {
            revert SwapAmountTooLarge();
        }

        state.pool = IUniswapV3Pool(
            factory.getPool(
                state.token0,
                state.token1,
                state.fee
            )
        );
        (state.amountOutMin, state.currentTick, , ) = _validateSwap(
            params.swap0To1,
            params.amountIn,
            state.pool,
            params.swap0To1
                ? config.token0SlippageX64
                : config.token1SlippageX64
        );

        if (
            state.currentTick < state.tickLower - config.lowerTickLimit ||
            state.currentTick >= state.tickUpper + config.upperTickLimit
        ) {
            int24 tickSpacing = _getTickSpacing(factory, state.fee);
            int24 baseTick = state.currentTick -
                (((state.currentTick % tickSpacing) + tickSpacing) %
                    tickSpacing);

            if (
                baseTick + config.lowerTickDelta == state.tickLower &&
                baseTick + config.upperTickDelta == state.tickUpper
            ) {
                revert SameRange();
            }

            (state.amountInDelta, state.amountOutDelta) = _safeSwap(
                params.swap0To1 ? state.token0 : state.token1,
                params.swap0To1 ? state.token1 : state.token0,
                params.amountIn,
                state.amountOutMin,
                params.swapData
            );

            state.amount0 = params.swap0To1
                ? state.amount0 - state.amountInDelta
                : state.amount0 + state.amountOutDelta;
            state.amount1 = params.swap0To1
                ? state.amount1 + state.amountOutDelta
                : state.amount1 - state.amountInDelta;
            state.maxAddAmount0 = config.onlyFees
                ? state.amount0
                : (state.amount0 * Q64) /
                (params.rewardX64 + Q64);
            state.maxAddAmount1 = config.onlyFees
                ? state.amount1
                : (state.amount1 * Q64) /
                (params.rewardX64 + Q64);

            INonfungiblePositionManager.MintParams
            memory mintParams = INonfungiblePositionManager.MintParams(
                address(state.token0),
                address(state.token1),
                state.fee,
                int24(baseTick + config.lowerTickDelta),
                int24(baseTick + config.upperTickDelta),
                state.maxAddAmount0,
                state.maxAddAmount1,
                0,
                0,
                address(this),
                params.deadline
            );

            state.token0.safeApprove(address(npm), state.maxAddAmount0);
            state.token1.safeApprove(address(npm), state.maxAddAmount1);

            (state.newTokenId, , state.amountAdded0, state.amountAdded1) = npm
            .mint(mintParams);

            state.token0.safeApprove(address(npm), 0);
            state.token1.safeApprove(address(npm), 0);

            state.owner = npm.ownerOf(params.tokenId);

            npm.safeTransferFrom(address(this), state.owner, state.newTokenId);

            if (!config.onlyFees) {
                state.protocolReward0 =
                    (state.amountAdded0 * params.rewardX64) /
                    Q64;
                state.protocolReward1 =
                    (state.amountAdded1 * params.rewardX64) /
                    Q64;
                state.amount0 -= state.protocolReward0;
                state.amount1 -= state.protocolReward1;
            }

            if (state.amount0 - state.amountAdded0 > 0) {
                _transferToken(
                    state.owner,
                    state.token0,
                    state.amount0 - state.amountAdded0,
                    true
                );
            }
            if (state.amount1 - state.amountAdded1 > 0) {
                _transferToken(
                    state.owner,
                    state.token1,
                    state.amount1 - state.amountAdded1,
                    true
                );
            }

            _addToken(state.owner, state.newTokenId);
            rangePositionConfigs[state.newTokenId] = config;
            emit RangeChanged(params.tokenId, state.newTokenId);
            emit RangePositionConfigured(
                state.newTokenId,
                config.lowerTickLimit,
                config.upperTickLimit,
                config.lowerTickDelta,
                config.upperTickDelta,
                config.token0SlippageX64,
                config.token1SlippageX64,
                config.onlyFees,
                config.maxRewardX64
            );

            _removeToken(state.owner, params.tokenId);
            delete rangePositionConfigs[params.tokenId];
        } else {
            revert NotReady();
        }
    }

    function configToken(uint256 tokenId, RangePositionConfig calldata config) external {
        address owner = ownerOf[tokenId];
        if (owner != msg.sender) {
            revert Unauthorized();
        }

        if (config.lowerTickDelta > config.upperTickDelta) {
            revert InvalidConfig();
        }

        rangePositionConfigs[tokenId] = config;

        emit RangePositionConfigured(
            tokenId,
            config.lowerTickLimit,
            config.upperTickLimit,
            config.lowerTickDelta,
            config.upperTickDelta,
            config.token0SlippageX64,
            config.token1SlippageX64,
            config.onlyFees,
            config.maxRewardX64
        );
    }

    function withdrawToken(
        uint256 tokenId,
        address to,
        bool withdrawBalances_,
        bytes memory data
    ) external nonReentrant {
        require(to != address(this));
        require(ownerOf[tokenId] == msg.sender);

        _removeToken(msg.sender, tokenId);
        npm.safeTransferFrom(address(this), to, tokenId, data);
        emit TokenWithdrawn(msg.sender, to, tokenId);

        if (withdrawBalances_) {
            (, , address token0, address token1, , , , , , , , ) = npm
                .positions(tokenId);
            _withdrawFullBalances(token0, token1, to);
        }
    }

    function withdrawBalance(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0);
        _transferToken(to, token, amount, false);
    }

    function withdrawBalances(
        address[] calldata tokens,
        address to
    ) external {
        if (msg.sender != operator) {
            revert Unauthorized();
        }

        uint i;
        uint count = tokens.length;
        for (; i < count; ++i) {
            uint256 balance = tokens[i].balanceOf(address(this));
            if (balance > 0) {
                _transferToken(to, tokens[i], balance, true);
            }
        }
    }

    function withdrawETH(address to) external {
        if (msg.sender != operator) {
            revert Unauthorized();
        }

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent, ) = to.call{value: balance}("");
            if (!sent) {
                revert EtherSendFailed();
            }
        }
    }

    function decreaseLiquidityAndCollect(DecreaseLiquidityAndCollectParams calldata params)
    external
    nonReentrant
    returns (uint256 amount0, uint256 amount1)
    {
        require(ownerOf[params.tokenId] == msg.sender, "!owner");
        (amount0, amount1) = npm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(
                params.tokenId,
                params.liquidity,
                params.amount0Min,
                params.amount1Min,
                params.deadline
            )
        );

        npm.collect(
            INonfungiblePositionManager.CollectParams(
                params.tokenId,
                params.recipient,
                YieldMath.toUint128(amount0),
                YieldMath.toUint128(amount1)
            )
        );
    }

    function collect(
        INonfungiblePositionManager.CollectParams calldata params
    )
    external
    nonReentrant
    returns (uint256 amount0, uint256 amount1)
    {
        require(ownerOf[params.tokenId] == msg.sender);
        return npm.collect(params);
    }

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external nonReentrant returns (bytes4) {
        require(msg.sender == address(npm));

        _addToken(from, tokenId);
        emit TokenDeposited(from, tokenId);
        return this.onERC721Received.selector;
    }

    function balanceOf(
        address account
    ) external view returns (uint256 balance) {
        return accountTokens[account].length;
    }

    function _increaseBalance(address account, address token, uint256 amount) internal {
        accountBalances[account][token] = accountBalances[account][token].rawAdd(
            amount
        );
        emit BalanceAdded(account, token, amount);
    }

    function _setBalance(address account, address token, uint256 amount) internal {
        uint currentBalance = accountBalances[account][token];

        accountBalances[account][token] = amount;

        if (amount > currentBalance) {
            emit BalanceAdded(
                account,
                address(token),
                amount.rawSub(currentBalance)
            );
        } else {
            emit BalanceRemoved(
                account,
                address(token),
                currentBalance.rawSub(amount)
            );
        }
    }

    function _withdrawFullBalances(
        address token0,
        address token1,
        address to
    ) internal {
        uint256 balance0 = accountBalances[msg.sender][token0];
        uint256 balance1 = accountBalances[msg.sender][token1];

        if (balance0 > 0) {
            _transferToken(to, token0, balance0, false);
        }
        if (balance1 > 0) {
            _transferToken(to, token1, balance1, false);
        }
    }

    function _addToken(address account, uint256 tokenId) internal {
        require(accountTokens[account].length < 100);

        (, , address token0, address token1, , , , , , , , ) = npm.positions(
            tokenId
        );

        uint256 allowance0 = IERC20(token0).allowance(address(this), address(npm));
        uint256 allowance1 = IERC20(token1).allowance(address(this), address(npm));

        if (allowance0 == 0) {
            token0.safeApprove(address(npm), type(uint256).max);
            token1.safeApprove(address(swapRouter), type(uint256).max);
        }
        if (allowance1 == 0) {
            token0.safeApprove(address(npm), type(uint256).max);
            token1.safeApprove(address(swapRouter), type(uint256).max);
        }
        accountTokens[account].push(tokenId);
        ownerOf[tokenId] = account;
    }

    function _removeToken(address account, uint256 tokenId) internal {
        uint256[] memory accountTokensArr = accountTokens[account];
        uint256 len = accountTokensArr.length;
        uint256 assetIndex = len;

        for (uint256 i = 0; i < len; i++) {
            if (accountTokensArr[i] == tokenId) {
                assetIndex = i;
                break;
            }
        }

        assert(assetIndex < len);

        uint256[] storage storedList = accountTokens[account];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        delete ownerOf[tokenId];
    }

    function _transferToken(
        address to,
        address token,
        uint256 amount,
        bool unwrap
    ) internal {
        accountBalances[msg.sender][token] = accountBalances[msg.sender][token]
            .rawSub(amount);
        emit BalanceRemoved(msg.sender, token, amount);
        if (address(weth) == token && unwrap) {
            weth.withdraw(amount);
            (bool sent, ) = to.call{value: amount}("");
            if (!sent) {
                revert EtherSendFailed();
            } else {
                emit BalanceWithdrawn(msg.sender, token, to, amount);
            }
        } else {
            token.safeTransfer(to, amount);
            emit BalanceWithdrawn(msg.sender, token, to, amount);
        }
    }

    function _getTickSpacing(IUniswapV3Factory factory, uint24 fee) internal view returns (int24) {
        if (fee == 10000) {
            return 200;
        } else if (fee == 3000) {
            return 60;
        } else if (fee == 500) {
            return 10;
        } else {
            int24 spacing = factory.feeAmountTickSpacing(fee);
            if (spacing <= 0) {
                revert NotSupportedFeeTier();
            }
            return spacing;
        }
    }

    receive() external payable {
        if (msg.sender != address(weth)) {
            revert NotWETH();
        }
    }
}
