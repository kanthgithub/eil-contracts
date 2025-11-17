// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/Helpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../AtomicSwapStorage.sol";
import "../bridges/IL2Bridge.sol";
import "../common/Errors.sol";
import "../common/utils/AtomicSwapUtils.sol";
import "../common/utils/BridgeMessengerLib.sol";
import "../common/utils/ChunkReportLib.sol";
import "../interfaces/IL1AtomicSwapStakeManager.sol";
import "../interfaces/IL2XlpDisputeManager.sol";
import "../types/Asset.sol";
import "../types/OriginInsolvencyChunk.sol";
import "../types/PendingDisputeReport.sol";
import "../types/ReportLegs.sol";
import "../types/SlashOutput.sol";
import "./OriginSwapBase.sol";

contract OriginationSwapDisputeManager is OriginSwapBase, IL2XlpDisputeManager {
    using AssetUtils for Asset;
    using AtomicSwapUtils for AtomicSwapVoucher;
    using AtomicSwapUtils for AtomicSwapVoucherRequest;

    constructor (
        uint256 _voucherUnlockDelay,
        uint256 _unstakeDelay,
        address _l2Connector,
        address _l1Connector,
        address _l1StakeManager,
        uint256 _userCancellationDelay,
        uint256 _voucherMinExpirationTime,
        uint256 _disputeBondPercent,
        uint256 _flatNativeBond,
        uint256 l1DisputeGasLimit
    )
        OriginSwapBase(
            _voucherUnlockDelay,
            _unstakeDelay,
            _userCancellationDelay,
            _voucherMinExpirationTime,
            _disputeBondPercent,
            _flatNativeBond,
            l1DisputeGasLimit
        )
    {
        l2Connector = IL2Bridge(_l2Connector);
        l1Connector = _l1Connector;
        l1StakeManager = _l1StakeManager;
    }

    /// @inheritdoc IL2XlpDisputeManager
    function onXlpSlashedMessage(SlashOutput calldata slashPayload) external override {
        require(address(l2Connector) == msg.sender, InvalidCaller("not L2 connector", address(l2Connector), msg.sender));
        address l1Sender = l2Connector.l1Sender();
        require(l1Connector == l1Sender, InvalidCaller("not L1 connector", l1Connector, l1Sender));
        address appSender = l2Connector.l1AppSender();
        require(l1StakeManager == appSender, InvalidCaller("not L1 stake manager", l1StakeManager, appSender));
        if (slashPayload.disputeType == DisputeType.INSOLVENT_XLP) {
            _justifiedDisputes[slashPayload.requestIdsHash] = true;
            return;
        }
        // Mark each disputed request as PENALIZED; no funds are moved here.
        bytes32[] storage requestIds = pendingDisputeBatches[slashPayload.requestIdsHash];
        for (uint256 i = 0; i < requestIds.length; i++) {
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestIds[i]];
            if (metadata.core.status == AtomicSwapStatus.DISPUTE) {
                metadata.core.status = AtomicSwapStatus.PENALIZED;
            }
        }
    }

    /// @inheritdoc IL2XlpDisputeManager
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
    ) external payable override {
        bytes32 reportId = _processInsolvencyDisputeChunk(
            disputeVouchers,
            l2XlpAddressToSlash,
            l1Beneficiary,
            chunkIndex,
            numberOfChunks,
            nonce,
            committedRequestIdsHash,
            committedVoucherCount
        );

        if (altVouchers.length > 0) {
            IOriginSwapManager(address(this)).issueAltVouchers(altVouchers);
        }

        PendingDisputeReport storage report = _pendingInsolvencyReports[reportId];
        if (report.core.expectedChunks == 0 || report.core.nextChunkIndex != report.core.expectedChunks) {
            return;
        }
        _finalizeInsolvencyReport(reportId, report);
    }

    /// @inheritdoc IL2XlpDisputeManager
    function disputeVoucherOverride(DisputeVoucher[] calldata disputeVouchers, address l2XlpAddressToSlash, address payable l1Beneficiary) external payable override {
        _initiateDisputeWithBond(disputeVouchers, l2XlpAddressToSlash, l1Beneficiary, DisputeType.VOUCHER_OVERRIDE);
    }

    /// @inheritdoc IL2XlpDisputeManager
    function disputeXlpUnspentVoucherClaim(DisputeVoucher[] calldata disputeVouchers, address payable l1Beneficiary) external payable override {
        require(disputeVouchers.length > 0, InvalidLength("No disputed vouchers", 0, disputeVouchers.length));
        bytes32 firstId = disputeVouchers[0].voucherRequest.getVoucherRequestId();
        AtomicSwapMetadata storage firstMetadata = outgoingAtomicSwaps[firstId];
        require(firstMetadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(firstId));
        address l2XlpAddressToSlash = firstMetadata.unspentFeeXlpRecipient;
        require(l2XlpAddressToSlash != address(0), UnspentClaimNotFound(firstId));
        for (uint256 i = 0; i < disputeVouchers.length; i++) {
            bytes32 requestId = disputeVouchers[i].voucherRequest.getVoucherRequestId();
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
            require(metadata.unspentFeeXlpRecipient == l2XlpAddressToSlash, InvalidCaller("mixed unspent recipient", l2XlpAddressToSlash, metadata.unspentFeeXlpRecipient));
        }
        _initiateDisputeWithBond(disputeVouchers, l2XlpAddressToSlash, l1Beneficiary, DisputeType.UNSPENT_VOUCHER_FEE_CLAIM);
    }

    function _processInsolvencyDisputeChunk(
        DisputeVoucher[] calldata disputeVouchers,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary,
        uint256 chunkIndex,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) internal returns (bytes32 reportId) {
        ChunkReportLib.validateChunkInputs(numberOfChunks, chunkIndex, disputeVouchers.length, "No disputed vouchers", 0);

        DisputeVoucher calldata firstVoucher = disputeVouchers[0];
        AtomicSwapVoucherRequest calldata firstRequest = firstVoucher.voucherRequest;
        bytes32 firstRequestId = firstRequest.getVoucherRequestId();
        AtomicSwapMetadata storage firstMetadata = outgoingAtomicSwaps[firstRequestId];
        require(firstMetadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(firstRequestId));
        require(
            firstRequest.origination.chainId == block.chainid,
            ChainIdMismatch(block.chainid, firstRequest.origination.chainId)
        );

        ChunkReportLib.ChunkContext memory disputeChunkContext = ChunkReportLib.buildContext(
            l2XlpAddressToSlash,
            msg.sender,
            l1Beneficiary,
            DisputeType.INSOLVENT_XLP,
            block.chainid,
            firstRequest.destination.chainId,
            numberOfChunks,
            nonce
        );
        PendingDisputeReport storage activeReport = _pendingInsolvencyReports[disputeChunkContext.reportId];

        if (chunkIndex == 0) {
            _initializeInsolvencyReport(
                activeReport,
                msg.sender,
                l2XlpAddressToSlash,
                l1Beneficiary,
                disputeChunkContext,
                numberOfChunks,
                nonce,
                committedRequestIdsHash,
                committedVoucherCount
            );
            emit InsolvencyReportStarted(
                disputeChunkContext.reportId,
                msg.sender,
                l2XlpAddressToSlash,
                l1Beneficiary,
                disputeChunkContext.origChainId,
                disputeChunkContext.destChainId,
                numberOfChunks,
                committedRequestIdsHash,
                committedVoucherCount,
                block.timestamp
            );
        } else {
            ChunkReportLib.requireExistingReport(activeReport.core);
        }

        ChunkReportLib.requireExpectedChunkIndex(activeReport.core, chunkIndex);

        ChunkIterationContext memory iterationContext = _firstChunkIterationContext(activeReport);
        bytes32[] memory requestIds = new bytes32[](disputeVouchers.length);

        for (uint256 i = 0; i < disputeVouchers.length; i++) {
            (iterationContext, requestIds[i]) = _processDisputeVoucher(
                disputeChunkContext.reportId,
                activeReport,
                iterationContext,
                disputeVouchers[i],
                l2XlpAddressToSlash,
                disputeChunkContext.destChainId,
                chunkIndex == 0 && i == 0
            );
        }

        require(msg.value == iterationContext.requiredNative, AmountMismatch("Native Bond", iterationContext.requiredNative, msg.value));

        _applyBondsAndMarkDispute(requestIds, disputeVouchers, l2XlpAddressToSlash, l1Beneficiary);

        _finalizeDisputeChunk(activeReport, requestIds, iterationContext, chunkIndex);

        emit InsolvencyReportChunk(disputeChunkContext.reportId, chunkIndex, numberOfChunks, disputeVouchers.length, block.timestamp);
        return disputeChunkContext.reportId;
    }

    function _initializeInsolvencyReport(
        PendingDisputeReport storage report,
        address reporter,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary,
        ChunkReportLib.ChunkContext memory context,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) internal {
        ChunkReportLib.initializeFirstChunk(
            report.core,
            originInsolvencyReportNonces,
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

        report.firstRequestedAt = 0;
        report.lastCreatedAt = 0;
        report.lastRequestId = bytes32(0);
        report.maxVoucherIssuedAt = 0;
    }

    function _firstChunkIterationContext(PendingDisputeReport storage report) internal view returns (ChunkIterationContext memory iteration) {
        if (report.core.totalVoucherCount == 0) {
            iteration.previousCreatedAt = 0;
            iteration.previousRequestId = bytes32(0);
        } else {
            iteration.previousCreatedAt = report.lastCreatedAt;
            iteration.previousRequestId = report.lastRequestId;
        }
    }

    function _processDisputeVoucher(
        bytes32 reportId,
        PendingDisputeReport storage report,
        ChunkIterationContext memory iteration,
        DisputeVoucher calldata disputeVoucher,
        address l2XlpAddressToSlash,
        uint256 expectedDestChainId,
        bool isFirstInChunk
    ) internal returns (ChunkIterationContext memory updatedIteration, bytes32 requestId) {
        AtomicSwapVoucherRequest calldata voucherRequest = disputeVoucher.voucherRequest;
        requestId = voucherRequest.getVoucherRequestId();
        AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
        require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));

        updatedIteration = iteration;
        originRequestInReport[reportId][requestId] = true;

        AtomicSwapStatus status = metadata.core.status;
        require(
            status == AtomicSwapStatus.VOUCHER_ISSUED || status == AtomicSwapStatus.DISPUTE,
            InvalidSwapStatus(requestId, status, AtomicSwapStatus.VOUCHER_ISSUED)
        );
        uint256 voucherIssuedAt = uint256(metadata.core.voucherIssuedAt);
        require(
            voucherIssuedAt < block.timestamp,
            ActionTooSoon("dispute too soon after issue", voucherIssuedAt, voucherIssuedAt + 1, block.timestamp)
        );
        require(
            voucherIssuedAt + TIME_TO_DISPUTE > block.timestamp,
            ActionTooLate("initiate dispute", voucherIssuedAt, voucherIssuedAt + TIME_TO_DISPUTE, block.timestamp)
        );
        require(metadata.core.voucherIssuerL2XlpAddress == l2XlpAddressToSlash, InvalidCaller("mixed xlps", l2XlpAddressToSlash, metadata.core.voucherIssuerL2XlpAddress));
        require(
            voucherRequest.origination.chainId == block.chainid,
            ChainIdMismatch(block.chainid, voucherRequest.origination.chainId)
        );
        require(voucherRequest.destination.chainId == expectedDestChainId, ChainIdMismatch(expectedDestChainId, voucherRequest.destination.chainId));

        uint256 createdAt = uint256(metadata.core.createdAt);
        if (report.core.totalVoucherCount == 0 && isFirstInChunk) {
            report.firstRequestedAt = createdAt;
        } else {
            _assertVoucherOrdering(updatedIteration.previousCreatedAt, updatedIteration.previousRequestId, createdAt, requestId);
        }

        updatedIteration.previousCreatedAt = createdAt;
        updatedIteration.previousRequestId = requestId;
        updatedIteration.requiredNative += _nativeRequiredForDispute(metadata, voucherRequest, disputeVoucher.bondType);
        if (voucherIssuedAt > report.maxVoucherIssuedAt) {
            report.maxVoucherIssuedAt = voucherIssuedAt;
        }
    }

    function _assertVoucherOrdering(
        uint256 previousCreatedAt,
        bytes32 previousRequestId,
        uint256 createdAt,
        bytes32 requestId
    ) internal pure {
        require(createdAt >= previousCreatedAt, InvalidOrdering("unsorted by createdAt"));
        if (createdAt == previousCreatedAt) {
            require(requestId > previousRequestId, InvalidOrdering("unsorted by requestId"));
        }
    }

    function _finalizeDisputeChunk(
        PendingDisputeReport storage report,
        bytes32[] memory requestIds,
        ChunkIterationContext memory iteration,
        uint256 chunkIndex
    ) internal {
        bytes32 chunkHash = keccak256(abi.encode(requestIds));
        ChunkReportLib.foldChunk(report.core, chunkHash, requestIds.length, chunkIndex);
        report.lastCreatedAt = iteration.previousCreatedAt;
        report.lastRequestId = iteration.previousRequestId;
    }

    function _finalizeInsolvencyReport(bytes32 reportId, PendingDisputeReport storage report) internal {

        bytes32 requestIdsHash = ChunkReportLib.finalizeCommitment(report.core);
        require(
            report.core.firstChunkSubmittedAt > report.maxVoucherIssuedAt,
            ChunkSubmittedBeforeLastVoucher(report.maxVoucherIssuedAt, report.core.firstChunkSubmittedAt)
        );

        _requestIdsHashByReportId[reportId] = requestIdsHash;

        _sendOriginReportLeg(
            report.core.xlpToSlash,
            requestIdsHash,
            report.core.origChainId,
            report.core.destChainId,
            report.core.l1Beneficiary,
            DisputeType.INSOLVENT_XLP,
            report.core.totalVoucherCount,
            report.firstRequestedAt,
            report.lastCreatedAt
        );

        delete _pendingInsolvencyReports[reportId];
    }

    /// @inheritdoc IL2XlpDisputeManager
    function reportJustifiedDisputeRequests(bytes32 reportId, bytes32[] calldata requestIds) external override {
        require(requestIds.length > 0, InvalidLength("No penalized vouchers", 0, requestIds.length));
        bytes32 requestIdsHash = _requestIdsHashByReportId[reportId];
        require(requestIdsHash != bytes32(0), InvalidReportId(bytes32(0), reportId));
        require(_justifiedDisputes[requestIdsHash], DisputeNotJustified(reportId));

        uint256 penalizedCount;
        bytes32 chunkHash = keccak256(abi.encode(requestIds));
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            bool tracked = originRequestInReport[reportId][requestId];
            require(tracked, RequestNotPartOfReport(reportId, requestId));

            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            if (metadata.core.status == AtomicSwapStatus.PENALIZED) {
                continue;
            }
            require(
                metadata.core.status == AtomicSwapStatus.DISPUTE,
                InvalidSwapStatus(requestId, metadata.core.status, AtomicSwapStatus.DISPUTE)
            );
            metadata.core.status = AtomicSwapStatus.PENALIZED;
            unchecked {penalizedCount++;}
        }

        emit JustifiedDisputeRequestsReported(
            reportId,
            requestIdsHash,
            msg.sender,
            chunkHash,
            requestIds.length,
            penalizedCount
        );
    }

    function _recordDisputeBond(AtomicSwapMetadata storage metadata, address token, uint256 amount) internal {
        metadata.disputeBondToken = token;
        metadata.disputeBondAmount = amount;
        metadata.disputeBondOwner = payable(msg.sender);
    }

    function _nativeRequiredForDispute(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest,
        BondType bondType
    ) internal view returns (uint256) {
        if (bondType == BondType.NATIVE) {
            return FLAT_NATIVE_BOND;
        }

        Asset memory firstAsset = voucherRequest.origination.assets[0];
        if (bondType == BondType.PERCENT && firstAsset.erc20Token == NATIVE_ETH) {
            uint256 bondPercent = _bondPercentAmount(metadata);
            return bondPercent;
        }

        return 0;
    }

    function _bondPercentAmount(AtomicSwapMetadata storage metadata) internal view returns (uint256) {
        uint256 amountAfterFee = metadata.amountsAfterFee[0];
        return _getAmountWithBond(amountAfterFee) - amountAfterFee;
    }

    function _initiateDisputeWithBond(
        DisputeVoucher[] calldata disputeVouchers,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary,
        DisputeType disputeType
    ) internal {
        require(disputeVouchers.length > 0, InvalidLength("No disputed vouchers", 0, 0));
        (bytes32[] memory requestIds, uint256 origChain, uint256 destChain, uint256 firstRequestedAt, uint256 lastRequestedAt) =
            _prepareDisputeBatch(disputeVouchers, l2XlpAddressToSlash, disputeType);
        uint256 totalNativeRequired = _computeTotalNativeRequired(disputeVouchers);
        require(msg.value == totalNativeRequired, AmountMismatch("Native Bond", totalNativeRequired, msg.value));
        _applyBondsAndMarkDispute(requestIds, disputeVouchers, l2XlpAddressToSlash, l1Beneficiary);
        bytes32 requestIdsHash = _computeRequestIdsHash(requestIds);
        pendingDisputeBatches[requestIdsHash] = requestIds;
        _sendOriginReportLeg(l2XlpAddressToSlash, requestIdsHash, origChain, destChain, l1Beneficiary, disputeType, requestIds.length, firstRequestedAt, lastRequestedAt);
    }

    function _prepareDisputeBatch(
        DisputeVoucher[] calldata disputeVouchers,
        address l2XlpAddressToSlash,
        DisputeType disputeType
    )
    internal view
    returns (bytes32[] memory requestIds, uint256 origChain, uint256 destChain, uint256 firstRequestedAt, uint256 lastRequestedAt)
    {
        uint256 length = disputeVouchers.length;
        requestIds = new bytes32[](length);

        uint256 lastCreatedAt;
        bytes32 lastRequestId;

        for (uint256 i = 0; i < length; i++) {
            AtomicSwapVoucherRequest calldata voucherRequest = disputeVouchers[i].voucherRequest;
            bytes32 requestId = voucherRequest.getVoucherRequestId();
            requestIds[i] = requestId;

            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));

            if (i == 0) {
                origChain = voucherRequest.origination.chainId;
                destChain = voucherRequest.destination.chainId;
                require(origChain == block.chainid, ChainIdMismatch(block.chainid, origChain));
                firstRequestedAt = uint256(metadata.core.createdAt);
            } else {
                require(voucherRequest.origination.chainId == origChain, ChainIdMismatch(origChain, voucherRequest.origination.chainId));
                require(voucherRequest.destination.chainId == destChain, ChainIdMismatch(destChain, voucherRequest.destination.chainId));
                _assertVoucherOrdering(lastCreatedAt, lastRequestId, uint256(metadata.core.createdAt), requestId);
            }

            AtomicSwapStatus status = metadata.core.status;
            require(
                status == AtomicSwapStatus.VOUCHER_ISSUED || status == AtomicSwapStatus.DISPUTE,
                InvalidSwapStatus(requestId, status, AtomicSwapStatus.VOUCHER_ISSUED)
            );
            uint256 voucherIssuedAt = uint256(metadata.core.voucherIssuedAt);
            require(
                voucherIssuedAt < block.timestamp,
                ActionTooSoon("dispute too soon after issue", voucherIssuedAt, voucherIssuedAt + 1, block.timestamp)
            );
            require(
                voucherIssuedAt + TIME_TO_DISPUTE > block.timestamp,
                ActionTooLate("initiate dispute", voucherIssuedAt, voucherIssuedAt + TIME_TO_DISPUTE, block.timestamp)
            );
            if (disputeType != DisputeType.UNSPENT_VOUCHER_FEE_CLAIM) {
                require(metadata.core.voucherIssuerL2XlpAddress == l2XlpAddressToSlash, InvalidCaller("mixed xlps", l2XlpAddressToSlash, metadata.core.voucherIssuerL2XlpAddress));
            }

            lastCreatedAt = uint256(metadata.core.createdAt);
            lastRequestId = requestId;
        }

        lastRequestedAt = lastCreatedAt;
    }

    function _computeTotalNativeRequired(DisputeVoucher[] calldata disputeVouchers) internal view returns (uint256 totalNativeRequired) {
        for (uint256 i = 0; i < disputeVouchers.length; i++) {
            AtomicSwapVoucherRequest calldata voucherRequest = disputeVouchers[i].voucherRequest;
            bytes32 requestId = voucherRequest.getVoucherRequestId();
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));

            if (disputeVouchers[i].bondType == BondType.NATIVE) {
                totalNativeRequired += FLAT_NATIVE_BOND;
            } else if (disputeVouchers[i].bondType == BondType.PERCENT && voucherRequest.origination.assets[0].erc20Token == NATIVE_ETH) {
                totalNativeRequired += _bondPercentAmount(metadata);
            }
        }
    }

    function _applyBondsAndMarkDispute(
        bytes32[] memory requestIds,
        DisputeVoucher[] calldata disputeVouchers,
        address l2XlpAddressToSlash,
        address payable l1Beneficiary
    ) internal {
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            AtomicSwapVoucherRequest calldata voucherRequest = disputeVouchers[i].voucherRequest;

            // If a previous disputer exists and is different, refund their bond and replace owner
            if (metadata.disputeBondAmount > 0 && metadata.disputeBondOwner != msg.sender) {
                _tokenIncrementDeposit(
                    Asset({erc20Token: metadata.disputeBondToken, amount: metadata.disputeBondAmount}),
                    metadata.disputeBondOwner
                );
                metadata.disputeBondToken = address(0);
                metadata.disputeBondAmount = 0;
                metadata.disputeBondOwner = payable(address(0));
            }

            if (disputeVouchers[i].bondType == BondType.NATIVE) {
                _collectDisputeBondNative(metadata, FLAT_NATIVE_BOND);
            } else if (voucherRequest.origination.assets[0].erc20Token == NATIVE_ETH) {
                uint256 bondAmount = _bondPercentAmount(metadata);
                _collectDisputeBondNative(metadata, bondAmount);
            } else {
                _collectDisputeBondErc20(metadata, voucherRequest);
            }

            metadata.core.status = AtomicSwapStatus.DISPUTE;
            emit DisputeInitiated(requestId, l2XlpAddressToSlash, msg.sender, l1Beneficiary);
        }
    }

    function _computeRequestIdsHash(bytes32[] memory requestIds) internal pure returns (bytes32) {
        return keccak256(abi.encode(requestIds));
    }

    function _sendOriginReportLeg(
        address l2XlpAddressToSlash,
        bytes32 requestIdsHash,
        uint256 origChain,
        uint256 destChain,
        address payable l1Beneficiary,
        DisputeType disputeType,
        uint256 count,
        uint256 firstRequestedAt,
        uint256 lastRequestedAt
    ) internal {
        ReportDisputeLeg memory leg = ReportDisputeLeg({
            requestIdsHash: requestIdsHash,
            originationChainId: origChain,
            destinationChainId: destChain,
            count: count,
            firstRequestedAt: firstRequestedAt,
            lastRequestedAt: lastRequestedAt,
            disputeTimestamp: block.timestamp,
            l1Beneficiary: l1Beneficiary,
            l2XlpAddressToSlash: l2XlpAddressToSlash,
            disputeType: disputeType
        });
        bytes memory callData = abi.encodeCall(IL1AtomicSwapStakeManager.reportOriginDispute, (leg));
        bytes memory forward = BridgeMessengerLib.sendMessageToL1(
            address(this),
            l2Connector,
            l1Connector,
            l1StakeManager,
            callData,
            L1_DISPUTE_GAS_LIMIT
        );
        emit MessageSentToL1(l1Connector, "forwardFromL2(report)", forward, L1_DISPUTE_GAS_LIMIT);
    }

    /// @notice After L1 slashing, a disputer can withdraw both the dispute bond and the override bond for vouchers it currently owns.
    /// @dev This implements: justified dispute → both bonds go to the disputer.
    function withdrawDisputeBonds(bytes32[] calldata requestIds) external override {
        for (uint256 i = 0; i < requestIds.length; i++) {
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestIds[i]];
            require(metadata.core.status == AtomicSwapStatus.PENALIZED, InvalidSwapStatus(requestIds[i], metadata.core.status, AtomicSwapStatus.PENALIZED));
            address bondOwner = metadata.disputeBondOwner;
            bool callerIsOwner = bondOwner == msg.sender;
            if (metadata.disputeBondAmount > 0 && callerIsOwner) {
                _tokenIncrementDeposit(
                    Asset({erc20Token: metadata.disputeBondToken, amount: metadata.disputeBondAmount}),
                    payable(msg.sender)
                );
                metadata.disputeBondToken = address(0);
                metadata.disputeBondAmount = 0;
                metadata.disputeBondOwner = payable(address(0));
            }
            // If there is an override bond, pay it to the same disputer (owner at time of call)
            if (metadata.overrideBondAmount > 0 && callerIsOwner) {
                _tokenIncrementDeposit(
                    Asset({erc20Token: metadata.overrideBondToken, amount: metadata.overrideBondAmount}),
                    payable(msg.sender)
                );
                metadata.overrideBondToken = address(0);
                metadata.overrideBondAmount = 0;
            }
        }
    }

    function _collectDisputeBondNative(AtomicSwapMetadata storage metadata, uint256 bondAmount) internal {
        _recordDisputeBond(metadata, NATIVE_ETH, bondAmount);
    }

    // Collect a dispute bond explicitly as ERC20 (10% of first asset-after-fee), ignoring msg.value.
    // Used when callers specify PERCENT to avoid mixed native/token batches interacting with msg.value.
    function _collectDisputeBondErc20(AtomicSwapMetadata storage metadata, AtomicSwapVoucherRequest calldata voucherRequest) internal {
        Asset memory firstAsset = voucherRequest.origination.assets[0];
        require(firstAsset.erc20Token != NATIVE_ETH, AmountMismatch("bond erc20", 0, msg.value));
        uint256 bondAmount = _bondPercentAmount(metadata);
        firstAsset.withAmount(bondAmount).secure(msg.sender);
        _recordDisputeBond(metadata, firstAsset.erc20Token, bondAmount);
    }
}
