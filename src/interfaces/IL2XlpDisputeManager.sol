// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IOriginSwapManager.sol";
import "../types/SlashOutput.sol";
import "../types/DisputeVoucher.sol";
import "../common/IL2XlpLogger.sol";

interface IL2XlpDisputeManager is IL2XlpLogger {

    event InsolvencyReportChunk(bytes32 indexed reportId, uint256 indexed chunkIndex, uint256 indexed numberOfChunks, uint256 chunkSize, uint256 chunkTimestamp);

    event DisputeInitiated(
        bytes32 indexed requestId,
        address indexed l2XlpAddressToSlash,
        address indexed disputer,
        address l1Beneficiary);

    event InsolvencyReportStarted(
        bytes32 indexed reportId,
        address indexed reporter,
        address indexed l2XlpAddressToSlash,
        address l1Beneficiary,
        uint256 originationChainId,
        uint256 destinationChainId,
        uint256 numberOfChunks,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount,
        uint256 firstChunkTimestamp
    );

    event JustifiedDisputeRequestsReported(
        bytes32 indexed reportId,
        bytes32 indexed reportRequestIdsHash,
        address indexed reporter,
        bytes32 chunkRequestIdsHash,
        uint256 providedCount,
        uint256 penalizedCount
    );

    /**
     * @notice Called on origin chain by the L1 stake manager after receiving slash message from destination chain.
     * @param slashOutput - group slash information (contains requestIdsHash).
     */
    function onXlpSlashedMessage(SlashOutput calldata slashOutput) external;

    /**
     * @notice Called by a slasher on the origin chain to prevent the swap from being withdrawn and start insolvency dispute.
     * @param disputeVouchers - per-request descriptor with optional ALT voucher and per-item bond type.
     * @param l2XlpAddressToSlash - address of the xlp that made a fraudulent atomic swap voucher.
     * @param l1Beneficiary - the beneficiary of the dispute if it is successful.
     */
    function disputeInsolventXlp(
        DisputeVoucher[] calldata disputeVouchers,
        VoucherWithRequest[] calldata altVouchers,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary,
        uint256 chunkIndex,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) external payable;

    /**
     * @notice Called by a slasher on the origin chain to prevent the swap from being withdrawn and start voucher override dispute.
     * @param disputeVouchers - per-request descriptor to allow per-item bond type selection.
     * @param l2XlpAddressToSlash - address of the xlp that made a fraudulent atomic swap voucher.
     * @param l1Beneficiary - the beneficiary of the dispute if it is successful.
     */
    function disputeVoucherOverride(DisputeVoucher[] calldata disputeVouchers, address l2XlpAddressToSlash, address payable l1Beneficiary) external payable;


    /**
     * @notice Called by a slasher on the origin chain to prevent the unspent voucher fee from being withdrawn and start the dispute.
     * @param disputeVouchers - per-request descriptor to allow per-item bond type selection.
     * @param l1Beneficiary - the beneficiary of the dispute if it is successful.
     */
    function disputeXlpUnspentVoucherClaim(DisputeVoucher[] calldata disputeVouchers, address payable l1Beneficiary) external payable;

    function withdrawDisputeBonds(bytes32[] calldata requestIds) external;

    function reportJustifiedDisputeRequests(bytes32 requestIdsHash, bytes32[] calldata requestIds) external;
}
