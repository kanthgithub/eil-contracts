// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct InsolvencyDisputePayout {
    bool partnersCounted;
    bool payoutAlreadyComputed;
    uint256 perRolePayout;
    uint256 leftoverWei;
}
