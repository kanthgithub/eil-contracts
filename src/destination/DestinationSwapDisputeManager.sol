// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./DestinationSwapBase.sol";
import "../common/utils/AtomicSwapUtils.sol";
import "../interfaces/IL1AtomicSwapStakeManager.sol";
import "../interfaces/IL2XlpPenalizer.sol";
import "../bridges/IL2Bridge.sol";
import "../common/Errors.sol";
import "../types/Asset.sol";
import "../types/ReportLegs.sol";
import "../types/PendingInsolvencyProof.sol";
import "../types/DestinationInsolvencyChunk.sol";
import "../AtomicSwapStorage.sol";
import "../common/utils/BridgeMessengerLib.sol";
import "../common/utils/ChunkReportLib.sol";

contract DestinationSwapDisputeManager is DestinationSwapBase, IL2XlpPenalizer {
    using AtomicSwapUtils for AtomicSwapVoucher;
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    function _disputeKey(address l2XlpAddressToSlash, uint256 origChainId, uint256 destChainId, DisputeType disputeType) internal pure returns (bytes32) {
        return keccak256(abi.encode(l2XlpAddressToSlash, origChainId, destChainId, disputeType));
    }

    constructor (address _l2Connector, address _l1Connector, address _entryPoint, uint256 l1SlashGasLimit)
        DestinationSwapBase(_entryPoint, l1SlashGasLimit)
    {
        l2Connector = IL2Bridge(_l2Connector);
        l1Connector = _l1Connector;
    }

    /// @inheritdoc IL2XlpPenalizer
    function accuseFalseVoucherOverride(AtomicSwapVoucherRequest[] calldata voucherRequests, AtomicSwapVoucher[] calldata voucherOverrides, address payable l1Beneficiary) public override {
        require(
            voucherRequests.length == voucherOverrides.length && voucherRequests.length > 0,
            InvalidLength("requests/overrides", voucherRequests.length, voucherOverrides.length)
        );
        (bool isRegisteredXlp,) = registeredXlps.tryGet(msg.sender);
        bytes32[] memory requestIds = new bytes32[](voucherRequests.length);
        address l2XlpAddressToSlash = voucherOverrides[0].originationXlpAddress;
        for (uint256 i = 0; i < voucherRequests.length; i++) {
            requestIds[i] = _processAccuseFalseVoucherOverride(
                voucherRequests[0],
                voucherRequests[i],
                voucherOverrides[i],
                isRegisteredXlp,
                l2XlpAddressToSlash,
                l1Beneficiary
            );
        }
        bytes32 requestIdsHash = keccak256(abi.encode(requestIds));
        {
            // Send destination report leg for longest-array selection
            ReportProofLeg memory leg = _buildProofLeg(
                requestIdsHash,
                voucherRequests[0].origination.chainId,
                voucherRequests[0].destination.chainId,
                voucherRequests.length,
                block.timestamp,
                0,
                l1Beneficiary,
                l2XlpAddressToSlash,
                DisputeType.VOUCHER_OVERRIDE
            );
            _forwardProofLegToL1(leg);
        }
    }

    function _processAccuseFalseVoucherOverride(
        AtomicSwapVoucherRequest calldata firstReq,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucherOverride,
        bool isRegisteredXlp,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary
    ) internal returns (bytes32 requestId) {
        AtomicSwapMetadataDestination storage atomicSwap;
        (requestId, atomicSwap) = _validateDestinationVoucherPair(firstReq, voucherRequest, voucherOverride);
        require(isRegisteredXlp, MsgSenderNotAllowedToPenalize(requestId, msg.sender, voucherRequest.destination.sender, isRegisteredXlp));
        require(atomicSwap.status == AtomicSwapStatus.SUCCESSFUL, InvalidAccusationVoucherNotPaid(requestId, l2XlpAddressToSlash));
        require(voucherOverride.voucherType == VoucherType.OVERRIDE,
            InvalidVoucherType(requestId, VoucherType.OVERRIDE, voucherOverride.voucherType));
        require(atomicSwap.paidByL2XlpAddress != l2XlpAddressToSlash, InvalidAccusationXlpPaid(requestId, l2XlpAddressToSlash));
        require(voucherOverride.originationXlpAddress == l2XlpAddressToSlash, InvalidCaller("mixed xlps", l2XlpAddressToSlash, voucherOverride.originationXlpAddress));
        emit FalseVoucherOverrideAccused(requestId, voucherOverride.originationXlpAddress, msg.sender, atomicSwap.paidByL2XlpAddress, l1Beneficiary);
    }

    /// @inheritdoc IL2XlpPenalizer
    function proveVoucherSpent(AtomicSwapVoucherRequest[] calldata voucherRequests, AtomicSwapVoucher[] calldata vouchers, address payable l1Beneficiary, address l2XlpAddressToSlash) public override {
        require(
            voucherRequests.length == vouchers.length && voucherRequests.length > 0,
            InvalidLength("requests/vouchers", voucherRequests.length, vouchers.length)
        );
        (bool isRegisteredXlp,) = registeredXlps.tryGet(msg.sender);
        bytes32[] memory requestIds = new bytes32[](voucherRequests.length);
        for (uint256 i = 0; i < voucherRequests.length; i++) {
            bytes32 requestId = _processProveVoucherSpent(voucherRequests[0], voucherRequests[i], vouchers[i], isRegisteredXlp);
            emit ProvenVoucherSpent(requestId, l2XlpAddressToSlash, msg.sender, l1Beneficiary);
            requestIds[i] = requestId;
        }
        bytes32 requestIdsHash = keccak256(abi.encode(requestIds));
        {
            // Destination report leg (unspent voucher claim false)
            ReportProofLeg memory leg = _buildProofLeg(
                requestIdsHash,
                voucherRequests[0].origination.chainId,
                voucherRequests[0].destination.chainId,
                voucherRequests.length,
                block.timestamp,
                0,
                l1Beneficiary,
                l2XlpAddressToSlash,
                DisputeType.UNSPENT_VOUCHER_FEE_CLAIM
            );
            _forwardProofLegToL1(leg);
        }
    }

    function _processProveVoucherSpent(
        AtomicSwapVoucherRequest calldata firstVoucherRequest,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher,
        bool isRegisteredXlp
    ) internal view returns (bytes32 requestId) {
        AtomicSwapMetadataDestination storage atomicSwap;
        (requestId, atomicSwap) = _validateDestinationVoucherPair(firstVoucherRequest, voucherRequest, voucher);
        require(
            msg.sender == voucherRequest.destination.sender || isRegisteredXlp,
            MsgSenderNotAllowedToPenalize(requestId, msg.sender, voucherRequest.destination.sender, isRegisteredXlp)
        );
        require(
            atomicSwap.status == AtomicSwapStatus.SUCCESSFUL,
            InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.SUCCESSFUL, atomicSwap.status)
        );
    }

    /// @inheritdoc IL2XlpPenalizer
    function proveXlpInsolvent(
        AtomicSwapVoucherRequest[] calldata voucherRequests,
        AtomicSwapVoucher[] calldata vouchers,
        address payable l1Beneficiary,
        uint256 chunkIndex,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) public override {
        require(voucherRequests.length == vouchers.length && voucherRequests.length > 0, InvalidLength("requests/vouchers", voucherRequests.length, vouchers.length));

        address l2XlpAddressToSlash = vouchers[0].originationXlpAddress;
        bytes32 reportId = _processInsolvencyProofChunk(
            voucherRequests,
            vouchers,
            l2XlpAddressToSlash,
            l1Beneficiary,
            chunkIndex,
            numberOfChunks,
            nonce,
            committedRequestIdsHash,
            committedVoucherCount
        );

        _finalizeInsolvencyProof(reportId);
    }

    function _forwardProofLegToL1(ReportProofLeg memory leg) internal {
        bytes memory reportData = abi.encodeCall(IL1AtomicSwapStakeManager.reportDestinationProof, (leg));
        bytes memory forwardCalldata = BridgeMessengerLib.sendMessageToL1(
            address(this),
            l2Connector,
            l1Connector,
            l1StakeManager,
            reportData,
            L1_SLASH_GAS_LIMIT
        );
        emit MessageSentToL1(l1Connector, "forwardFromL2(report)", forwardCalldata, L1_SLASH_GAS_LIMIT);
    }

    function _initializeInsolvencyProofReport(
        PendingInsolvencyProof storage report,
        address reporter,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary,
        ChunkReportLib.ChunkContext memory context,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) internal {
        uint256 chunkTimestamp = ChunkReportLib.initializeFirstChunk(
            report.core,
            destinationInsolvencyReportNonces,
            reporter,
            l2XlpAddressToSlash,
            l1Beneficiary,
            context.origChainId,
            context.destChainId,
            numberOfChunks,
            nonce,
            committedRequestIdsHash,
            committedVoucherCount
        );
        report.disputeKey = _disputeKey(l2XlpAddressToSlash, context.origChainId, context.destChainId, DisputeType.INSOLVENT_XLP);

        uint256 recorded = _firstProve[report.disputeKey];
        if (recorded == 0 || chunkTimestamp < recorded) {
            _firstProve[report.disputeKey] = chunkTimestamp;
        }
    }

    function _prepareDestinationIteration(uint256 length)
        internal
        pure
        returns (DestinationChunkIterationState memory iteration)
    {
        iteration.requestIds = new bytes32[](length);
    }

    function _processProofVoucher(
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher,
        bool isRegisteredXlp,
        address l2XlpAddressToSlash,
        uint256 expectedOriginationChainId,
        address payable l1Beneficiary
    ) internal returns (bytes32 requestId) {
        requestId = _proveInsolventVoucher(
            voucherRequest,
            voucher,
            isRegisteredXlp,
            l2XlpAddressToSlash,
            expectedOriginationChainId
        );

        emit ProvenXlpInsolvent(requestId, l2XlpAddressToSlash, msg.sender, l1Beneficiary);
    }

    function _updateProofAggregation(
        PendingInsolvencyProof storage report,
        bytes32[] memory requestIds,
        uint256 chunkIndex
    ) internal {
        bytes32 chunkHash = keccak256(abi.encode(requestIds));
        ChunkReportLib.foldChunk(report.core, chunkHash, requestIds.length, chunkIndex);
    }

    function _buildInsolvencyProofLeg(
        PendingInsolvencyProof storage report,
        bytes32 requestIdsHash,
        uint256 proofTimestamp,
        uint256 earliestProof
    ) internal view returns (ReportProofLeg memory) {
        return _buildProofLeg(
            requestIdsHash,
            report.core.origChainId,
            report.core.destChainId,
            report.core.totalVoucherCount,
            proofTimestamp,
            earliestProof,
            report.core.l1Beneficiary,
            report.core.xlpToSlash,
            DisputeType.INSOLVENT_XLP
        );
    }

    function _buildProofLeg(
        bytes32 requestIdsHash,
        uint256 origChainId,
        uint256 destChainId,
        uint256 count,
        uint256 proofTimestamp,
        uint256 firstProveTimestamp,
        address payable l1Beneficiary,
        address l2XlpAddressToSlash,
        DisputeType disputeType
    ) internal pure returns (ReportProofLeg memory) {
        return ReportProofLeg({
            requestIdsHash: requestIdsHash,
            originationChainId: origChainId,
            destinationChainId: destChainId,
            count: count,
            proofTimestamp: proofTimestamp,
            firstProveTimestamp: firstProveTimestamp,
            l1Beneficiary: l1Beneficiary,
            l2XlpAddressToSlash: l2XlpAddressToSlash,
            disputeType: disputeType
        });
    }

    function _validateDestinationVoucherPair(
        AtomicSwapVoucherRequest calldata firstVoucherRequest,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher
    )
        internal
        view
        returns (bytes32 requestId, AtomicSwapMetadataDestination storage atomicSwap)
    {
        requestId = AtomicSwapUtils.getVoucherRequestId(voucherRequest);
        require(requestId == voucher.requestId, VoucherRequestIdMismatch(requestId, voucher.requestId));

        atomicSwap = incomingAtomicSwaps[requestId];

        require(voucherRequest.destination.chainId == block.chainid, ChainIdMismatch(block.chainid, voucherRequest.destination.chainId));
        voucher.verifyVoucherSignature(voucherRequest.destination);

        require(
            voucherRequest.origination.chainId == firstVoucherRequest.origination.chainId,
            ChainIdMismatch(firstVoucherRequest.origination.chainId, voucherRequest.origination.chainId)
        );
        require(
            voucherRequest.destination.chainId == firstVoucherRequest.destination.chainId,
            ChainIdMismatch(firstVoucherRequest.destination.chainId, voucherRequest.destination.chainId)
        );
    }

    function _processInsolvencyProofChunk(
        AtomicSwapVoucherRequest[] calldata voucherRequests,
        AtomicSwapVoucher[] calldata vouchers,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary,
        uint256 chunkIndex,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) internal returns (bytes32 reportId) {
        ChunkReportLib.validateChunkInputs(numberOfChunks, chunkIndex, voucherRequests.length, "No vouchers", voucherRequests.length);

        AtomicSwapVoucherRequest calldata firstVoucherRequest = voucherRequests[0];
        ChunkReportLib.ChunkContext memory context = ChunkReportLib.buildContext(
            l2XlpAddressToSlash,
            msg.sender,
            l1Beneficiary,
            DisputeType.INSOLVENT_XLP,
            firstVoucherRequest.origination.chainId,
            firstVoucherRequest.destination.chainId,
            numberOfChunks,
            nonce
        );

        PendingInsolvencyProof storage activeReport = _pendingInsolvencyProofs[context.reportId];

        if (chunkIndex == 0) {
            _initializeInsolvencyProofReport(
                activeReport,
                msg.sender,
                l2XlpAddressToSlash,
                l1Beneficiary,
                context,
                numberOfChunks,
                nonce,
                committedRequestIdsHash,
                committedVoucherCount
            );
            emit InsolvencyProofStarted(
                context.reportId,
                msg.sender,
                l2XlpAddressToSlash,
                l1Beneficiary,
                context.origChainId,
                context.destChainId,
                numberOfChunks,
                committedRequestIdsHash,
                committedVoucherCount,
                block.timestamp
            );
        } else {
            ChunkReportLib.requireExistingReport(activeReport.core);
        }

        ChunkReportLib.requireExpectedChunkIndex(activeReport.core, chunkIndex);

        (bool isRegisteredXlp,) = registeredXlps.tryGet(msg.sender);

        DestinationChunkIterationState memory iteration = _prepareDestinationIteration(voucherRequests.length);

        for (uint256 i = 0; i < voucherRequests.length; i++) {
            iteration.requestIds[i] = _processProofVoucher(
                voucherRequests[i],
                vouchers[i],
                isRegisteredXlp,
                l2XlpAddressToSlash,
                context.origChainId,
                l1Beneficiary
            );
        }

        _updateProofAggregation(activeReport, iteration.requestIds, chunkIndex);

        emit InsolvencyProofChunk(context.reportId, chunkIndex, numberOfChunks, voucherRequests.length, block.timestamp);
        return context.reportId;
    }

    function _finalizeInsolvencyProof(bytes32 reportId) internal {
        PendingInsolvencyProof storage report = _pendingInsolvencyProofs[reportId];
        if (report.core.expectedChunks == 0 || report.core.nextChunkIndex != report.core.expectedChunks) {
            return;
        }

        bytes32 requestIdsHash = ChunkReportLib.finalizeCommitment(report.core);

        uint256 finalTimestamp = block.timestamp;
        uint256 earliest = _firstProve[report.disputeKey];
        if (earliest == 0) {
            earliest = finalTimestamp;
            _firstProve[report.disputeKey] = earliest;
        }

        ReportProofLeg memory leg = _buildInsolvencyProofLeg(report, requestIdsHash, finalTimestamp, earliest);
        _forwardProofLegToL1(leg);

        delete _pendingInsolvencyProofs[reportId];
    }

    function _requireInsufficientXlpBalance(
        bytes32 requestId,
        address l2XlpAddress,
        Asset[] memory assets,
        uint256 maxUserOpCost
    ) internal view {
        bool isBalanceSufficient = _hasSufficientXlpBalance(l2XlpAddress, assets, maxUserOpCost);
        if (isBalanceSufficient) {
            revert InvalidAccusationXlpHasSufficientBalance(requestId, l2XlpAddress, assets);
        }
    }

    function _hasSufficientXlpBalance(
        address l2XlpAddress,
        Asset[] memory assets,
        uint256 maxUserOpCost
    ) internal view returns (bool) {
        uint256 requiredNativeEthAmount = maxUserOpCost;
        for (uint256 i = 0; i < assets.length; i++) {
            address token = assets[i].erc20Token;
            uint256 balance = balances[token][l2XlpAddress];
            if (token == NATIVE_ETH) {
                requiredNativeEthAmount += assets[i].amount;
            } else if (balance < assets[i].amount) {
                return false;
            }
        }
        if (balances[NATIVE_ETH][l2XlpAddress] < requiredNativeEthAmount) {
            return false;
        }
        return true;
    }

    function _proveInsolventVoucher(
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher,
        bool isRegisteredXlp,
        address l2XlpAddressToSlash,
        uint256 originChainId
    ) internal returns (bytes32 requestId) {
        requestId = AtomicSwapUtils.getVoucherRequestId(voucherRequest);
        require(requestId == voucher.requestId, VoucherRequestIdMismatch(requestId, voucher.requestId));
        require(
            msg.sender == voucherRequest.destination.sender || isRegisteredXlp,
            MsgSenderNotAllowedToPenalize(requestId, msg.sender, voucherRequest.destination.sender, isRegisteredXlp)
        );
        AtomicSwapMetadataDestination storage atomicSwap = incomingAtomicSwaps[requestId];
        // Already reported by another reporter, no need to check again
        if (atomicSwap.status == AtomicSwapStatus.PENALIZED) {
            return requestId;
        }
        // Allow re-proving only when initial status is NONE or already PENALIZED (for tie-break updates).
        require(
            atomicSwap.status == AtomicSwapStatus.NONE,
            InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.NONE, atomicSwap.status)
        );
        voucher.verifyVoucherSignature(voucherRequest.destination);
        require(voucherRequest.destination.chainId == block.chainid, ChainIdMismatch(block.chainid, voucherRequest.destination.chainId));
        require(voucherRequest.origination.chainId == originChainId, ChainIdMismatch(originChainId, voucherRequest.origination.chainId));
        // Voucher must still be valid when proving insolvency
        _verifyVoucherNotExpired(voucherRequest.destination, voucher);
        require(voucher.originationXlpAddress == l2XlpAddressToSlash, InvalidCaller("mixed xlps", l2XlpAddressToSlash, voucher.originationXlpAddress));
        _requireInsufficientXlpBalance(
            voucher.requestId,
            l2XlpAddressToSlash,
            voucherRequest.destination.assets,
            voucherRequest.destination.maxUserOpCost
        );
        // Mark penalized on first proof
        atomicSwap.status = AtomicSwapStatus.PENALIZED;
    }
}
