// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Asset.sol";

// describe the swap's target chain requested tokens
struct DestinationSwapComponent {
    uint256 chainId;
    address paymaster;
    address payable sender;
    Asset[] assets;
    uint256 maxUserOpCost;
    uint256 expiresAt;
}
