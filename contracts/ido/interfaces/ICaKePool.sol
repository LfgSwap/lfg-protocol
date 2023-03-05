// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface ICaKePool {
    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 shares; // number of shares for a user.
        uint256 lastDepositedTime; // keep track of deposited time for potential penalty.
        uint256 lockStartTime; // lock start time.
        uint256 lockEndTime; // lock end time.
        bool locked; //lock status.
        uint256 rewardDebt;
    }

    function userInfo(address _user) external view returns (UserInfo memory);
}