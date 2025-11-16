// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct PendingSlashPayout {
    address l1XlpAddress;
    address payable beneficiary;
    uint256 amount; // 90% of total stake at slash time
    uint256 claimableAt;
    bool paid;
}
