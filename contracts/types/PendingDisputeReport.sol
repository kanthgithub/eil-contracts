// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../common/utils/ChunkReportLib.sol";

struct PendingDisputeReport {
    /// @dev Shared chunk bookkeeping used by origin/destination dispute flows.
    ChunkReportLib.ChunkReportState core;
    /// @dev Creation timestamp (on origin) of the earliest disputed voucher in the report.
    uint256 firstRequestedAt;
    /// @dev Creation timestamp of the latest disputed voucher processed so far.
    uint256 lastCreatedAt;
    /// @dev Request id of the latest disputed voucher processed so far; used as a tie-breaker for ordering checks.
    bytes32 lastRequestId;
    /// @dev Highest voucherIssuedAt observed while processing the dispute; used to enforce sequential windows.
    uint256 maxVoucherIssuedAt;
}
