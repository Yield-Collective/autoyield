// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract YieldBase is Ownable {
    event RewardUpdated(address account, uint64 totalRewardX64, uint64 compounderRewardX64);
    event OperatorChanged(address newOperator, bool active);
    event TWAPConfigUpdated(address account, uint16 maxTWAPTickDifference, uint32 TWAPSeconds);
    event WithdrawerChanged(address newWithdrawer);
    event SwapRouterChanged(address swapRouterReBalancer);

    error InvalidConfig();

    uint128 constant Q64 = 2**64;
    uint128 constant Q96 = 2**96;
    uint64 constant public MAX_REWARD_X64 = uint64(Q64 / 50);
    uint32 public constant MIN_TWAP_SECONDS = 60;
    uint32 public constant MAX_TWAP_TICK_DIFFERENCE = 200;
    uint64 public totalRewardX64 = MAX_REWARD_X64;
    uint64 public compounderRewardX64 = MAX_REWARD_X64 / 2;
    /// @notice Max tick difference between TWAP tick and current price to allow operations
    uint16 public maxTWAPTickDifference = 100;
    /// @notice Number of seconds to use for TWAP calculation
    uint32 public TWAPSeconds = 60;
    address public swapRouterReBalance;
    address public withdrawer;
    mapping(address => bool) public operators;

    /**
     * @notice Management method to lower reward or change ratio between total and compounder reward (onlyOwner)
     * @param _totalRewardX64 new total reward (can't be higher than current total reward)
     * @param _compounderRewardX64 new compounder reward
     */
    function setReward(uint64 _totalRewardX64, uint64 _compounderRewardX64) external onlyOwner {
        require(_totalRewardX64 <= totalRewardX64, ">totalRewardX64");
        require(_compounderRewardX64 <= _totalRewardX64, "compounderRewardX64>totalRewardX64");
        totalRewardX64 = _totalRewardX64;
        compounderRewardX64 = _compounderRewardX64;
        emit RewardUpdated(msg.sender, _totalRewardX64, _compounderRewardX64);
    }

    function setSwapRouterReBalance(address _swapRouterReBalance) external onlyOwner {
        emit SwapRouterChanged(_swapRouterReBalance);
        swapRouterReBalance = _swapRouterReBalance;
    }

    function setWithdrawer(address _withdrawer) public onlyOwner {
        emit WithdrawerChanged(_withdrawer);
        withdrawer = _withdrawer;
    }

    function setOperator(address _operator, bool _active) public onlyOwner {
        emit OperatorChanged(_operator, _active);
        operators[_operator] = _active;
    }

    function setTWAPConfig(uint16 _maxTWAPTickDifference, uint32 _TWAPSeconds) public  {
        if (_TWAPSeconds < MIN_TWAP_SECONDS) {
            revert InvalidConfig();
        }
        if (_maxTWAPTickDifference > MAX_TWAP_TICK_DIFFERENCE) {
            revert InvalidConfig();
        }

        TWAPSeconds = _TWAPSeconds;
        maxTWAPTickDifference = _maxTWAPTickDifference;
        emit TWAPConfigUpdated(msg.sender, _maxTWAPTickDifference, _TWAPSeconds);
    }
}