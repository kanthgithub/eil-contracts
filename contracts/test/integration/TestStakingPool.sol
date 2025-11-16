// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestStakingPool is Ownable {
    IERC20 public immutable stakeToken;

    mapping(address => uint256) public userStake;
    mapping(address => uint256) public rewards;

    constructor(IERC20 _token) Ownable(msg.sender) {
        stakeToken = _token;
    }

    /* -------- admin -------- */

    function sudoFund(uint256 amount) external onlyOwner {
        stakeToken.transferFrom(msg.sender, address(this), amount);
    }

    function sudoSetCurrentReward(address user, uint256 amount) external onlyOwner {
        rewards[user] = amount;
    }

    /* -------- user -------- */

    function stake(uint256 amount) external {
        userStake[msg.sender] += amount;
        stakeToken.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        userStake[msg.sender] -= amount;
        stakeToken.transfer(msg.sender, amount);
    }

    function claim() external {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        stakeToken.transfer(msg.sender, reward);
    }
}
