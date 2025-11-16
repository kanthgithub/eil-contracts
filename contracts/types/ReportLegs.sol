// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Enums.sol";

/// @notice Origin-side grouped dispute report leg (sent L2->L1)
/// @dev All arrays are grouped into a strictly ordered, deduplicated list on L2.
struct ReportDisputeLeg {
    // Request ids hash computed as keccak256(abi.encode(chunkHashes)), where each chunk hash is
    // keccak256(abi.encode(requestIdsChunk)). Shared by both legs for matching on L1.
    bytes32 requestIdsHash;
    // Chain pair
    uint256 originationChainId;
    uint256 destinationChainId;
    // Number of vouchers in the group
    uint256 count;
    // Bounds by creation timestamp on origin (strict ordering enforced on L2)
    uint256 firstRequestedAt;
    uint256 lastRequestedAt;
    // Timestamp on origin when the dispute transaction was sent
    uint256 disputeTimestamp;
    // L1 beneficiary that should receive the origin winner share for this report
    address payable l1Beneficiary;
    // The L2 xlp being slashed (L2 identity)
    address l2XlpAddressToSlash;
    // Dispute type for this set
    DisputeType disputeType;
}

/// @notice Destination-side grouped proof report leg (sent L2->L1)
/// @dev Carries the timestamp of the proof for tie-break rules.
struct ReportProofLeg {
    // Request ids hash, matching the origin leg definition (nested hash of chunk hashes)
    bytes32 requestIdsHash;
    // Chain pair
    uint256 originationChainId;
    uint256 destinationChainId;
    // Number of vouchers in the group
    uint256 count;
    // Timestamp on destination when proof was produced (used for tie-break)
    uint256 proofTimestamp;
    // Earliest successful destination prove timestamp for this (xlp, pair, dispute type)
    // Used by L1 to split pre/post windows deterministically regardless of pairing order
    uint256 firstProveTimestamp;
    // L1 beneficiary that should receive the destination winner share for this report
    address payable l1Beneficiary;
    // The L2 xlp being slashed (L2 identity)
    address l2XlpAddressToSlash;
    // Dispute type for this set
    DisputeType disputeType;
}
