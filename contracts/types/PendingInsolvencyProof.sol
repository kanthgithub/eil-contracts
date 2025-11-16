// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../common/utils/ChunkReportLib.sol";

struct PendingInsolvencyProof {
    ChunkReportLib.ChunkReportState core;
    bytes32 disputeKey;
}
