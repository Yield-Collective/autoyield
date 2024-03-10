// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import "./interfaces/IAutoYield.sol";
import "./lib/YieldMath.sol";
import "./lib/YieldSwap.sol";

contract AutoYield is IAutoYield, ReentrancyGuard, Multicall, Ownable {
    using SafeMath for uint256;
    address public operator;

    INonfungiblePositionManager public override npm;
    ISwapRouter public override swapRouter;
    address public immutable override weth;
    address public immutable override factory;

    mapping(uint256 => RangePositionConfig) public rangePositionConfigs;
    mapping(uint256 => address) public override ownerOf;
    mapping(address => uint256[]) public override accountTokens;
    mapping(address => mapping(address => uint256)) public override accountBalances;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, ISwapRouter _swapRouter)
    {
        npm = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
        factory = npm.factory();
        weth = npm.WETH9();

        operator = msg.sender;
    }

    function withdrawBalances(address[] calldata tokens, address to) external override {
        if (msg.sender != operator) {
            revert Unauthorized();
        }

        uint i;
        uint count = tokens.length;
        for(;i < count;++i) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
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
            (bool sent,) = to.call{value: balance}("");
            if (!sent) {
                revert EtherSendFailed();
            }
        }
    }

    function reBalance(RangeExecuteParams calldata params) external {
        if (msg.sender != operator) {
            revert Unauthorized();
        }

        RangeExecuteState memory state;
        RangePositionConfig memory config = rangePositionConfigs[params.tokenId];

        if (config.lowerTickDelta == config.upperTickDelta) {
            revert NotConfigured();
        }

        if (config.onlyFees && params.rewardX64 > config.maxRewardX64 || !config.onlyFees && params.rewardX64 > config.maxRewardX64) {
            revert ExceedsMaxReward();
        }

        (,, state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, state.liquidity, , , , ) =  npm.positions(params.tokenId);

        if (state.liquidity != params.liquidity) {
            revert LiquidityChanged();
        }

        (state.amount0, state.amount1, state.feeAmount0, state.feeAmount1) = YieldSwap.decreaseFullLiquidityAndCollect(npm, params.tokenId, state.liquidity, params.amountRemoveMin0, params.amountRemoveMin1, params.deadline);

        if (config.onlyFees) {
            state.protocolReward0 = state.feeAmount0 * params.rewardX64 / YieldSwap.Q64;
            state.protocolReward1 = state.feeAmount1 * params.rewardX64 / YieldSwap.Q64;
            state.amount0 -= state.protocolReward0;
            state.amount1 -= state.protocolReward1;
        }

        if (params.swap0To1 && params.amountIn > state.amount0 || !params.swap0To1 && params.amountIn > state.amount1) {
            revert SwapAmountTooLarge();
        }

        state.pool = YieldSwap.getPool(factory, state.token0, state.token1, state.fee);
        (state.amountOutMin,state.currentTick,,) = YieldSwap.validateSwap(params.swap0To1, params.amountIn, state.pool, params.swap0To1 ? config.token0SlippageX64 : config.token1SlippageX64);

        if (state.currentTick < state.tickLower - config.lowerTickLimit || state.currentTick >= state.tickUpper + config.upperTickLimit) {
            int24 tickSpacing = YieldMath.getTickSpacing(factory, state.fee);
            int24 baseTick = state.currentTick - (((state.currentTick % tickSpacing) + tickSpacing) % tickSpacing);

            if (baseTick + config.lowerTickDelta == state.tickLower && baseTick + config.upperTickDelta == state.tickUpper) {
                revert SameRange();
            }

            (state.amountInDelta, state.amountOutDelta) = YieldSwap.safeSwap(address(swapRouter), params.swap0To1 ? IERC20(state.token0) : IERC20(state.token1), params.swap0To1 ? IERC20(state.token1) : IERC20(state.token0), params.amountIn, state.amountOutMin, params.swapData);

            state.amount0 = params.swap0To1 ? state.amount0 - state.amountInDelta : state.amount0 + state.amountOutDelta;
            state.amount1 = params.swap0To1 ? state.amount1 + state.amountOutDelta : state.amount1 - state.amountInDelta;
            state.maxAddAmount0 = config.onlyFees ? state.amount0 : state.amount0 * YieldSwap.Q64 / (params.rewardX64 + YieldSwap.Q64);
            state.maxAddAmount1 = config.onlyFees ? state.amount1 : state.amount1 * YieldSwap.Q64 / (params.rewardX64 + YieldSwap.Q64);

            INonfungiblePositionManager.MintParams memory mintParams =
                                INonfungiblePositionManager.MintParams(
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

            SafeERC20.safeApprove(IERC20(state.token0), address(npm), state.maxAddAmount0);
            SafeERC20.safeApprove(IERC20(state.token1), address(npm), state.maxAddAmount1);

            (state.newTokenId,,state.amountAdded0,state.amountAdded1) = npm.mint(mintParams);

            SafeERC20.safeApprove(IERC20(state.token0), address(npm), 0);
            SafeERC20.safeApprove(IERC20(state.token1), address(npm), 0);

            state.owner = npm.ownerOf(params.tokenId);

            npm.safeTransferFrom(address(this), state.owner, state.newTokenId);

            if (!config.onlyFees) {
                state.protocolReward0 = state.amountAdded0 * params.rewardX64 / YieldSwap.Q64;
                state.protocolReward1 = state.amountAdded1 * params.rewardX64 / YieldSwap.Q64;
                state.amount0 -= state.protocolReward0;
                state.amount1 -= state.protocolReward1;
            }

            if (state.amount0 - state.amountAdded0 > 0) {
                _transferToken(state.owner, state.token0, state.amount0 - state.amountAdded0, true);
            }
            if (state.amount1 - state.amountAdded1 > 0) {
                _transferToken(state.owner, state.token1, state.amount1 - state.amountAdded1, true);
            }

            rangePositionConfigs[state.newTokenId] = config;
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

            delete rangePositionConfigs[params.tokenId];
            emit RangePositionConfigured(params.tokenId, 0, 0, 0, 0, 0, 0, false, 0);
            emit RangeChanged(params.tokenId, state.newTokenId);
        } else {
            revert NotReady();
        }
    }

    function configToken(uint256 tokenId, RangePositionConfig calldata config) external {
        address owner = npm.ownerOf(tokenId);
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

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override nonReentrant returns (bytes4) {
        require(msg.sender == address(npm));

        _addToken(tokenId, from);
        emit TokenDeposited(from, tokenId);
        return this.onERC721Received.selector;
    }

    function balanceOf(address account) override external view returns (uint256 balance) {
        return accountTokens[account].length;
    }

    function autoCompound(AutoCompoundParams memory params)
        override 
        external 
        nonReentrant
        returns (uint256 reward0, uint256 reward1, uint256 compounded0, uint256 compounded1)
    {
        require(ownerOf[params.tokenId] != address(0));

        AutoCompoundState memory state;
        (state.amount0, state.amount1) = npm.collect(
            INonfungiblePositionManager.CollectParams(params.tokenId, address(this), type(uint128).max, type(uint128).max)
        );
        (, , state.token0, state.token1, state.fee, state.tickLower, state.tickUpper, , , , , ) = 
            npm.positions(params.tokenId);

        state.tokenOwner = ownerOf[params.tokenId];
        state.amount0 = state.amount0.add(accountBalances[state.tokenOwner][state.token0]);
        state.amount1 = state.amount1.add(accountBalances[state.tokenOwner][state.token1]);

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

            (state.amount0, state.amount1, state.priceX96, state.maxAddAmount0, state.maxAddAmount1) = 
                YieldSwap.swapToPriceRatio(factory, swapRouter, swapParams);

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
            (amount0Fees, amount1Fees) = YieldSwap.calculateCompoundFee(
                params.rewardConversion,
                state.amount0,
                state.amount1,
                state.priceX96,
                compounded0,
                compounded1,
                isNotOwner
            );

            _setBalance(state.tokenOwner, state.token0, state.amount0.sub(compounded0).sub(amount0Fees));
            _setBalance(state.tokenOwner, state.token1, state.amount1.sub(compounded1).sub(amount1Fees));

            if (isNotOwner) {
                uint64 protocolRewardX64 = YieldSwap.totalRewardX64 - YieldSwap.compounderRewardX64;
                uint256 protocolFees0 = amount0Fees.mul(protocolRewardX64).div(YieldSwap.totalRewardX64);
                uint256 protocolFees1 = amount1Fees.mul(protocolRewardX64).div(YieldSwap.totalRewardX64);

                reward0 = amount0Fees.sub(protocolFees0);
                reward1 = amount1Fees.sub(protocolFees1);

                _increaseBalance(msg.sender, state.token0, reward0);
                _increaseBalance(msg.sender, state.token1, reward1);
                _increaseBalance(owner(), state.token0, protocolFees0);
                _increaseBalance(owner(), state.token1, protocolFees1);
            }
        }

        if (params.withdrawReward) {
            _withdrawFullBalances(state.token0, state.token1, msg.sender);
        }

        emit AutoCompounded(msg.sender, params.tokenId, compounded0, compounded1, reward0, reward1, state.token0, state.token1);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params) 
        override 
        external
        nonReentrant 
        returns (uint256 amount0, uint256 amount1) 
    {
        require(ownerOf[params.tokenId] == msg.sender);
        return npm.collect(params);
    }

    function withdrawToken(
        uint256 tokenId,
        address to,
        bool withdrawBalances_,
        bytes memory data
    ) external override nonReentrant {
        require(to != address(this));
        require(ownerOf[tokenId] == msg.sender);

        _removeToken(msg.sender, tokenId);
        npm.safeTransferFrom(address(this), to, tokenId, data);
        emit TokenWithdrawn(msg.sender, to, tokenId);

        if (withdrawBalances_) {
            (, , address token0, address token1, , , , , , , , ) = npm.positions(tokenId);
            _withdrawFullBalances(token0, token1, to);
        }
    }

    function withdrawBalance(address token, address to, uint256 amount) external override nonReentrant {
        require(amount > 0);
        _transferToken(to, token, amount, false);
    }

    function _increaseBalance(address account, address token, uint256 amount) internal {
        accountBalances[account][token] = accountBalances[account][token].add(amount);
        emit BalanceAdded(account, token, amount);
    }

    function _setBalance(address account, address token, uint256 amount) internal {
        uint currentBalance = accountBalances[account][token];

        accountBalances[account][token] = amount;

        if (amount > currentBalance) {
            emit BalanceAdded(account, address(token), amount.sub(currentBalance));
        } else if (amount < currentBalance) {
            emit BalanceRemoved(account, address(token), currentBalance.sub(amount));
        }
    }

    function _withdrawFullBalances(address token0, address token1, address to) internal {
        uint256 balance0 = accountBalances[msg.sender][token0];
        uint256 balance1 = accountBalances[msg.sender][token1];

        if (balance0 > 0) {
            _transferToken(to, token0, balance0, false);
        }
        if (balance1 > 0) {
            _transferToken(to, token1, balance1, false);
        }
    }

    function _addToken(uint256 tokenId, address account) internal {
        require(accountTokens[account].length < 100);

        (, , address token0, address token1, , , , , , , , ) = npm.positions(tokenId);

        IERC20 tokenA = IERC20(token0);
        IERC20 tokenB = IERC20(token1);

        SafeERC20.forceApprove(tokenA, address(npm), type(uint256).max);
        SafeERC20.forceApprove(tokenB, address(npm), type(uint256).max);
        SafeERC20.forceApprove(tokenA, address(swapRouter), type(uint256).max);
        SafeERC20.forceApprove(tokenB, address(swapRouter), type(uint256).max);

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

    function _transferToken(address to, address token, uint256 amount, bool unwrap) internal {
        accountBalances[msg.sender][token] = accountBalances[msg.sender][token].sub(amount);
        emit BalanceRemoved(msg.sender, token, amount);
        if (weth == token && unwrap) {
            IWETH9(weth).withdraw(amount);
            (bool sent, ) = to.call{value: amount}("");
            if (!sent) {
                revert EtherSendFailed();
            } else {
                emit BalanceWithdrawn(msg.sender, token, to, amount);
            }
        } else {
            SafeERC20.safeTransfer(IERC20(token), to, amount);
            emit BalanceWithdrawn(msg.sender, token, to, amount);
        }
    }

    receive() external payable {
        if (msg.sender != address(weth)) {
            revert NotWETH();
        }
    }
}