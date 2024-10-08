// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./IYieldSwapper.sol";
import "./IUniswapV3Immutables.sol";

interface IAutoYield is IERC721Receiver, IYieldSwapper, IUniswapV3Immutables {
    // token movements
    event TokenDeposited(address account, uint256 tokenId);
    event TokenWithdrawn(address account, address to, uint256 tokenId);

    // balance movements
    event BalanceAdded(address account, address token, uint256 amount);
    event BalanceRemoved(address account, address token, uint256 amount);
    event BalanceWithdrawn(address account, address token, address to, uint256 amount);

    // autocompound event
    event AutoCompounded(
        address account,
        uint256 tokenId,
        uint256 amountAdded0,
        uint256 amountAdded1,
        uint256 reward0,
        uint256 reward1,
        address token0,
        address token1
    );

    event RangeChanged(
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId
    );
    event RangePositionConfigured(
        uint256 indexed tokenId,
        int32 lowerTickLimit,
        int32 upperTickLimit,
        int32 lowerTickDelta,
        int32 upperTickDelta,
        uint64 token0SlippageX64,
        uint64 token1SlippageX64,
        bool onlyFees,
        uint64 maxRewardX64
    );

    error SameRange();
    error NotReady();
    error Unauthorized();
    error EtherSendFailed();
    error NotWETH();
    error NotConfigured();
    error ExceedsMaxReward();
    error LiquidityChanged();
    error SwapAmountTooLarge();
    error InvalidConfig();
    error NotSupportedFeeTier();

    // defines when and how a position can be changed by operator
    // when a position is adjusted config for the position is cleared and copied to the newly created position
    struct RangePositionConfig {
        // needs more than int24 because it can be [-type(uint24).max,type(uint24).max]
        int32 lowerTickLimit; // if negative also in-range positions may be adjusted / if 0 out of range positions may be adjusted
        int32 upperTickLimit; // if negative also in-range positions may be adjusted / if 0 out of range positions may be adjusted
        int32 lowerTickDelta; // this amount is added to current tick (floored to tickspacing) to define lowerTick of new position
        int32 upperTickDelta; // this amount is added to current tick (floored to tickspacing) to define upperTick of new position
        uint64 token0SlippageX64; // max price difference from current pool price for swap / Q64 for token0
        uint64 token1SlippageX64; // max price difference from current pool price for swap / Q64 for token1
        bool onlyFees; // if only fees maybe used for protocol reward
        uint64 maxRewardX64; // max allowed reward percentage of fees or full position
    }

/// @notice params for reBalance()
    struct RangeExecuteParams {
        uint256 tokenId;
        bool swap0To1;
        uint256 amountIn; // if this is set to 0 no swap happens
        bytes swapData;
        uint128 liquidity; // liquidity the calculations are based on
        uint256 amountRemoveMin0; // min amount to be removed from liquidity
        uint256 amountRemoveMin1; // min amount to be removed from liquidity
        uint256 deadline; // for uniswap operations - operator promises fair value
        uint64 rewardX64;  // which reward will be used for protocol, can be max configured amount (considering onlyFees)
    }

    struct RangeExecuteState {
        address owner;
        address currentOwner;
        IUniswapV3Pool pool;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        int24 currentTick;

        uint256 amount0;
        uint256 amount1;
        uint256 feeAmount0;
        uint256 feeAmount1;

        uint256 maxAddAmount0;
        uint256 maxAddAmount1;

        uint256 amountAdded0;
        uint256 amountAdded1;

        uint128 liquidity;

        uint256 protocolReward0;
        uint256 protocolReward1;
        uint256 amountOutMin;
        uint256 amountInDelta;
        uint256 amountOutDelta;

        uint256 newTokenId;
    }

// state used during autocompound execution
    struct AutoCompoundState {
        uint256 amount0;
        uint256 amount1;
        uint256 maxAddAmount0;
        uint256 maxAddAmount1;
        uint256 amount0Fees;
        uint256 amount1Fees;
        uint256 priceX96;
        address tokenOwner;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice params for autoCompound()
    struct AutoCompoundParams {
        // tokenid to autocompound
        uint256 tokenId;

        // which token to convert to
        RewardConversion rewardConversion;

        // should token be withdrawn to compounder immediately
        bool withdrawReward;

        // do swap - to add max amount to position (costs more gas)
        bool doSwap;
    }

    struct DecreaseLiquidityAndCollectParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        address recipient;
    }

    /// @notice Owner of a managed NFT
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @notice Tokens of account by index
    function accountTokens(address account, uint256 index) external view returns (uint256 tokenId);

    /**
     * @notice Returns amount of NFTs for a given account
     * @param account Address of account
     * @return balance amount of NFTs for account
     */
    function balanceOf(address account) external view returns (uint256 balance);

    /**
     * @notice Returns balance of token of account
     * @param account Address of account
     * @param token Address of token
     * @return balance amount of token for account
     */
    function accountBalances(address account, address token) external view returns (uint256 balance);

    /**
     * @notice Removes a NFT from the protocol and safe transfers it to address to
     * @param tokenId TokenId of token to remove
     * @param to Address to send to
     * @param withdrawBalances_ When true sends the available balances for token0 and token1 as well
     * @param data data which is sent with the safeTransferFrom call (optional)
     */
    function withdrawToken(
        uint256 tokenId,
        address to,
        bool withdrawBalances_,
        bytes memory data
    ) external;

    /**
     * @notice Removes balances
     * @param tokens Array of Address of token to remove
     * @param to Address to send to)
     */
    function withdrawBalances(address[] calldata tokens, address to) external;

    /**
     * @notice Withdraws token balance for a address and token
     * @param token Address of token to withdraw
     * @param to Address to send to
     * @param amount amount to withdraw
     */
    function withdrawBalance(address token, address to, uint256 amount) external;

    /**
     * @notice Autocompounds for a given NFT (anyone can call this and gets a percentage of the fees)
     * @param params Autocompound specific parameters (tokenId, ...)
     * @return reward0 Amount of token0 caller recieves
     * @return reward1 Amount of token1 caller recieves
     * @return compounded0 Amount of token0 that was compounded
     * @return compounded1 Amount of token1 that was compounded
     */
    function autoCompound(AutoCompoundParams calldata params) external returns (uint256 reward0, uint256 reward1, uint256 compounded0, uint256 compounded1);

    function autoRange(address swapRouter_, RangeExecuteParams calldata params) external;

    /**
     * @notice Special method to decrease liquidity and collect decreased amount - can only be called by the NFT owner
     * @dev Needs to do collect at the same time, otherwise the available amount would be autocompoundable for other positions
     * @param params DecreaseLiquidityAndCollectParams which are forwarded to the Uniswap V3 NonfungiblePositionManager
     * @return amount0 amount of token0 removed and collected
     * @return amount1 amount of token1 removed and collected
     */
    function decreaseLiquidityAndCollect(DecreaseLiquidityAndCollectParams calldata params)
    external
    returns (uint256 amount0, uint256 amount1);
    /**
     * @notice Forwards collect call to NonfungiblePositionManager - can only be called by the NFT owner
     * @param params INonfungiblePositionManager.CollectParams which are forwarded to the Uniswap V3 NonfungiblePositionManager
     * @return amount0 amount of token0 collected
     * @return amount1 amount of token1 collected
     */
    function collect(INonfungiblePositionManager.CollectParams calldata params) external returns (uint256 amount0, uint256 amount1);
}