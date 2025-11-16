// SPDX-License-Identifier: MIT
/* solhint-disable max-states-count */
pragma solidity ^0.8.28;

import "./bridges/IL2Bridge.sol";
import "./types/AtomicSwapMetadata.sol";
import "./types/AtomicSwapMetadataDestination.sol";
import "./types/PendingInsolvencyProof.sol";
import "./types/PendingDisputeReport.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

/**
 * @title AtomicSwapStorage
 * @notice Base storage contract for atomic swap functionality.
 * @dev Inheritable storage contract that manages xlp registrations and connector addresses.
 */
contract AtomicSwapStorage {
    // Shared storage
    address public l1StakeManager;
    address public l1Connector;
    IL2Bridge public l2Connector;
    EnumerableMap.AddressToAddressMap internal registeredXlps;
    mapping(address xlp => address l2XlpAddress) public reverseLookup;
    mapping(address token => mapping(address account => uint256 balance)) internal balances;

    // Destination swap storage
    mapping(bytes32 requestId => AtomicSwapMetadataDestination atomicSwap) internal incomingAtomicSwaps;
    mapping(bytes32 disputeKey => uint256 firstProveTimestamp) internal _firstProve;
    mapping(bytes32 reportId => PendingInsolvencyProof) internal _pendingInsolvencyProofs;
    mapping(address reporter => uint256 nonce) internal destinationInsolvencyReportNonces;

    // Origin swap storage
    mapping(address sender => uint256 originationNonce) internal outgoingNonces;
    mapping(bytes32 requestId => AtomicSwapMetadata atomicSwap) internal outgoingAtomicSwaps;
    mapping(bytes32 requestId => mapping(address l2XlpAddress => uint256 timestamp)) internal xlpVoucherOverrideTimestamps;
    mapping(bytes32 requestIdsHash => bytes32[] requestIds) internal pendingDisputeBatches;
    mapping(bytes32 reportId => PendingDisputeReport) internal _pendingInsolvencyReports;
    mapping(address xlp => uint256 nonce) internal originInsolvencyReportNonces;
    mapping(bytes32 reportId => mapping(bytes32 requestId => bool)) internal originRequestInReport;
    mapping(bytes32 reportId => bytes32 requestIdsHash) internal _requestIdsHashByReportId;
    mapping(bytes32 requestIdsHash => bool) internal _justifiedDisputes;
}
