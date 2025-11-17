// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/Helpers.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../AtomicSwapStorage.sol";
import "../common/Errors.sol";
import "../common/utils/AssetUtils.sol";
import "../common/utils/AtomicSwapUtils.sol";
import "../interfaces/IL2XlpDisputeManager.sol";
import "../interfaces/IOriginSwapManager.sol";
import "../types/Asset.sol";
import "../types/Constants.sol";
import "../types/DisputeVoucher.sol";
import "../types/Enums.sol";
import "../types/SlashOutput.sol";
import "./OriginSwapBase.sol";

contract OriginSwapManager is OriginSwapBase, IOriginSwapManager, IL2XlpDisputeManager {
    using AssetUtils for Asset;
    using EnumerableMap for EnumerableMap.AddressToAddressMap;
    using AtomicSwapUtils for AtomicSwapVoucher;
    using AtomicSwapUtils for AtomicSwapVoucherRequest;
    using SafeERC20 for IERC20;

    address internal immutable _originDisputeModule;

    constructor(
        uint256 _voucherUnlockDelay,
        uint256 _timeBeforeDisputeExpires,
        uint256 _userCancellationDelay,
        uint256 _voucherMinExpirationTime,
        uint256 _disputeBondPercent,
        uint256 _flatNativeBond,
        address originModule,
        uint256 l1DisputeGasLimit
    )
        OriginSwapBase(
            _voucherUnlockDelay,
            _timeBeforeDisputeExpires,
            _userCancellationDelay,
            _voucherMinExpirationTime,
            _disputeBondPercent,
            _flatNativeBond,
            l1DisputeGasLimit
        )
    {
        _originDisputeModule = originModule;
    }

    /// @inheritdoc IOriginSwapManager
    function getSenderNonce(address sender) external view returns (uint256) {
        return outgoingNonces[sender];
    }

    /// @inheritdoc IOriginSwapManager
    function getVoucherOverrideTimestamp(bytes32 requestId, address l2XlpAddress) external view returns (uint256) {
        return xlpVoucherOverrideTimestamps[requestId][l2XlpAddress];
    }

    /// @inheritdoc IOriginSwapManager
    function getAtomicSwapMetadata(bytes32 requestId) external view returns (AtomicSwapMetadata memory metadata) {
        return outgoingAtomicSwaps[requestId];
    }

    /// @inheritdoc IOriginSwapManager
    function lockUserDeposit(AtomicSwapVoucherRequest calldata voucherRequest) public payable {
        require(
            voucherRequest.destination.expiresAt >= block.timestamp,
            VoucherRequestExpired(voucherRequest.getVoucherRequestId(), voucherRequest.destination.expiresAt, block.timestamp)
        );

        require(voucherRequest.origination.chainId == block.chainid, ChainIdMismatch(block.chainid, voucherRequest.origination.chainId));
        require(voucherRequest.origination.paymaster == address(this), AddressMismatch(address(this), voucherRequest.origination.paymaster));
        require(voucherRequest.origination.sender == msg.sender, InvalidCaller("not sender", voucherRequest.origination.sender, msg.sender));
        require(
            voucherRequest.origination.senderNonce == outgoingNonces[voucherRequest.origination.sender],
            NonceMismatch(voucherRequest.origination.senderNonce, outgoingNonces[voucherRequest.origination.sender])
        );
        outgoingNonces[voucherRequest.origination.sender]++;
        bytes32 requestId = voucherRequest.getVoucherRequestId();
        _secureOriginationAssets(voucherRequest);
        AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
        AtomicSwapStatus status = metadata.core.status;
        require(status == AtomicSwapStatus.NONE, InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.NONE, status));
        outgoingAtomicSwaps[requestId] = _buildInitialMetadata();
        emit VoucherRequestCreated(requestId, voucherRequest.origination.sender, voucherRequest);
    }

    /// @inheritdoc IOriginSwapManager
    function issueVouchers(VoucherWithRequest[] calldata vouchersWithRequests) external {
        for (uint256 i = 0; i < vouchersWithRequests.length; i++) {
            VoucherWithRequest calldata voucherWithRequest = vouchersWithRequests[i];
            bytes32 requestId = voucherWithRequest.voucher.requestId;
            _requireMatchingRequest(requestId, voucherWithRequest.voucherRequest);
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            _issueVoucher(metadata, voucherWithRequest.voucherRequest, voucherWithRequest.voucher, requestId);
        }
    }

    /// @inheritdoc IOriginSwapManager
    /// @notice Issue alternative vouchers during dispute (STANDARD->ALT or OVERRIDE->ALT_OVERRIDE)
    function issueAltVouchers(VoucherWithRequest[] calldata vouchersWithRequests) public {
        for (uint256 i = 0; i < vouchersWithRequests.length; i++) {
            VoucherWithRequest calldata voucherWithRequest = vouchersWithRequests[i];
            bytes32 requestId = voucherWithRequest.voucher.requestId;
            _requireMatchingRequest(requestId, voucherWithRequest.voucherRequest);
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            _issueAltVoucher(metadata, voucherWithRequest.voucherRequest, voucherWithRequest.voucher, requestId);
        }
    }

    function _issueVoucher(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher,
        bytes32 requestId
    ) internal {
        AtomicSwapStatus status = metadata.core.status;
        require(status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
        voucher.verifyVoucherSignature(voucherRequest.destination);
        _verifyAllowedXlp(voucherRequest, voucher.originationXlpAddress);
        uint256 createdAt = uint256(metadata.core.createdAt);
        require(
            createdAt + USER_CANCELLATION_DELAY - 1 minutes >= block.timestamp,
            ActionTooLate("issue voucher", createdAt, createdAt + USER_CANCELLATION_DELAY - 1 minutes, block.timestamp)
        );
        require(
            voucher.expiresAt >= block.timestamp + VOUCHER_MIN_EXPIRATION_TIME,
            VoucherExpiresTooSoon(voucher.requestId, voucher.expiresAt, block.timestamp)
        );
        require(status == AtomicSwapStatus.NEW, InvalidSwapStatus(requestId, status, AtomicSwapStatus.NEW));
        require(
            voucher.voucherType == VoucherType.STANDARD,
            InvalidVoucherType(voucher.requestId, VoucherType.STANDARD, voucher.voucherType)
        );
        _updateVoucherIssued(metadata, voucherRequest, voucher);
        _processAtomicSwapFeeRefund(metadata, voucherRequest);
    }

    function _issueAltVoucher(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher,
        bytes32 requestId
    ) internal {
        // Only allow while in dispute window
        AtomicSwapStatus status = metadata.core.status;
        require(status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
        require(status == AtomicSwapStatus.DISPUTE, InvalidSwapStatus(requestId, status, AtomicSwapStatus.DISPUTE));
        _assertAltVoucherTransition(metadata.core.voucherType, voucher.voucherType, requestId);
        voucher.verifyVoucherSignature(voucherRequest.destination);
        _verifyAllowedXlp(voucherRequest, voucher.originationXlpAddress);
        require(
            voucher.expiresAt >= block.timestamp + VOUCHER_MIN_EXPIRATION_TIME,
            VoucherExpiresTooSoon(voucher.requestId, voucher.expiresAt, block.timestamp)
        );
        // Preserve DISPUTE status after updating issuer/type since the funds are locked for the whole fraud proof window anyway.
        _updateVoucherIssued(metadata, voucherRequest, voucher);
        if (status == AtomicSwapStatus.DISPUTE) {
            metadata.core.status = AtomicSwapStatus.DISPUTE;
        }
    }

    /// @inheritdoc IOriginSwapManager
    function overrideVoucher(AtomicSwapVoucherRequest calldata voucherRequest, AtomicSwapVoucher calldata voucherOverride) external payable {
        bytes32 requestId = voucherOverride.requestId;
        _requireMatchingRequest(requestId, voucherRequest);
        AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
        _verifyVoucherOverride(metadata, voucherRequest, voucherOverride, requestId);
        // collect the override bond (either 10% of first asset or 0.1 ETH)
        _collectOverrideBond(metadata, voucherRequest);
        _updateVoucherIssued(metadata, voucherRequest, voucherOverride);
        xlpVoucherOverrideTimestamps[requestId][voucherOverride.originationXlpAddress] = block.timestamp;
    }

    function _verifyVoucherOverride(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucherOverride,
        bytes32 requestId
    ) internal view {
        AtomicSwapStatus status = metadata.core.status;
        require(status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
        require(status == AtomicSwapStatus.VOUCHER_ISSUED,
            InvalidSwapStatus(requestId, status, AtomicSwapStatus.VOUCHER_ISSUED));
        _assertOverrideVoucherTransition(metadata.core.voucherType, voucherOverride.voucherType, voucherOverride.requestId);
        voucherOverride.verifyVoucherSignature(voucherRequest.destination);
        _verifyAllowedXlp(voucherRequest, voucherOverride.originationXlpAddress);
    }

    function _updateVoucherIssued(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest,
        AtomicSwapVoucher calldata voucher
    ) internal {
        metadata.core.status = AtomicSwapStatus.VOUCHER_ISSUED;
        metadata.core.voucherIssuerL2XlpAddress = payable(voucher.originationXlpAddress);
        metadata.core.voucherIssuedAt = uint40(block.timestamp);
        metadata.core.voucherExpiresAt = uint40(voucher.expiresAt);
        metadata.core.voucherType = voucher.voucherType;
        emit VoucherIssued(
            voucher.requestId,
            voucherRequest.origination.sender,
            voucherRequest.origination.senderNonce,
            voucher
        );
    }

    /// @inheritdoc IOriginSwapManager
    function withdrawFromUserDeposit(AtomicSwapVoucherRequest[] calldata voucherRequests) external {
        for (uint256 i = 0; i < voucherRequests.length; i++) {
            AtomicSwapVoucherRequest calldata voucherRequest = voucherRequests[i];
            bytes32 requestId = voucherRequest.getVoucherRequestId();
            AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
            require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
            _withdrawUserDeposit(metadata, voucherRequest, requestId);
        }
    }

    function _withdrawUserDeposit(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest,
        bytes32 requestId
    ) internal {
        bool staleDispute = _requireVoucherIssuedOrStaleDisputed(metadata, requestId);
        // Always credit the base amounts to the voucher issuer
        uint256 assetCount = voucherRequest.origination.assets.length;
        require(assetCount == metadata.amountsAfterFee.length, AmountMismatch("amountsAfterFee length", assetCount, metadata.amountsAfterFee.length));
        for (uint256 i = 0; i < assetCount; i++) {
            Asset memory creditedAsset = Asset({
                erc20Token: voucherRequest.origination.assets[i].erc20Token,
                amount: metadata.amountsAfterFee[i]
            });
            _tokenIncrementDeposit(creditedAsset, metadata.core.voucherIssuerL2XlpAddress);
        }
        // If bonds were posted, credit them appropriately
        _refundOverrideBond(metadata);
        if (staleDispute) {
            _refundDisputeBondIfPosted(metadata);
        }
        metadata.core.status = AtomicSwapStatus.SUCCESSFUL;
        emit UserDepositWithdrawn(requestId, voucherRequest.origination.sender, metadata.core.voucherIssuerL2XlpAddress);
    }

    /// @inheritdoc IOriginSwapManager
    function cancelVoucherRequest(AtomicSwapVoucherRequest calldata voucherRequest) external {
        bytes32 requestId = voucherRequest.getVoucherRequestId();
        AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
        require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
        require(voucherRequest.origination.sender == msg.sender, InvalidCaller("not sender", voucherRequest.origination.sender, msg.sender));
        AtomicSwapStatus status = metadata.core.status;
        require(status == AtomicSwapStatus.NEW, InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.NEW, status));
        require(
            uint256(metadata.core.createdAt) + USER_CANCELLATION_DELAY <= block.timestamp,
            ActionTooSoon("request cancellation", metadata.core.createdAt, uint256(metadata.core.createdAt) + USER_CANCELLATION_DELAY, block.timestamp)
        );
        metadata.core.status = AtomicSwapStatus.CANCELLED;
        for (uint256 i = 0; i < voucherRequest.origination.assets.length; i++) {
            Asset memory asset = voucherRequest.origination.assets[i];
            asset.transfer(voucherRequest.origination.sender);
        }
        emit VoucherRequestCancelled(requestId, voucherRequest.origination.sender);
    }

    /// @inheritdoc IOriginSwapManager
    function claimUnspentVoucherFee(AtomicSwapVoucherRequest calldata voucherRequest) external {
        bytes32 requestId = voucherRequest.getVoucherRequestId();
        AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
        require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
        // Only registered xlps can call
//        _verifyAllowedXlp(atomicSwap.voucherRequest, msg.sender);
        (bool found,) = registeredXlps.tryGet(msg.sender);
        require(found, XlpNotRegistered(msg.sender));
        AtomicSwapStatus status = metadata.core.status;
        require(status == AtomicSwapStatus.VOUCHER_ISSUED, InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.VOUCHER_ISSUED, status));
        // Require voucher to be expired and dispute window not closed
        uint256 voucherExpiresAt = metadata.core.voucherExpiresAt;
        require(voucherExpiresAt < block.timestamp, ActionTooSoon("voucher expired", voucherExpiresAt, uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE, block.timestamp));
        require(
            uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE > block.timestamp,
            ActionTooLate("Cannot claim after dispute window", metadata.core.voucherIssuedAt, uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE, block.timestamp)
        );
        require(metadata.unspentFeeXlpRecipient == payable(0), UnspentFeeAlreadyClaimed(requestId, metadata.unspentFeeXlpRecipient));

        metadata.unspentFeeXlpRecipient = payable(msg.sender);
        emit UnspentVoucherFeeClaimed(requestId, voucherRequest.origination.sender, msg.sender, metadata.core.voucherIssuerL2XlpAddress);
    }

    /// @inheritdoc IOriginSwapManager
    function withdrawUnspentVoucherFee(AtomicSwapVoucherRequest calldata voucherRequest) external {
        bytes32 requestId = voucherRequest.getVoucherRequestId();
        AtomicSwapMetadata storage metadata = outgoingAtomicSwaps[requestId];
        require(metadata.core.status != AtomicSwapStatus.NONE, UnknownRequestId(requestId));
        AtomicSwapStatus status = metadata.core.status;
        require(status == AtomicSwapStatus.VOUCHER_ISSUED, InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.VOUCHER_ISSUED, status));
        require(metadata.unspentFeeXlpRecipient == msg.sender, InvalidCaller("Only reporting xlp", metadata.unspentFeeXlpRecipient, msg.sender));
        require(
            uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE < block.timestamp,
            ActionTooSoon("Cannot withdraw before dispute window", uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE, 0, block.timestamp)
        );
        // Withdraw fee
        metadata.core.status = AtomicSwapStatus.UNSPENT;
        _withdrawUnspentFeeAndUnlockDeposit(metadata, voucherRequest);
        emit UnspentVoucherFeeWithdrawn(requestId, voucherRequest.origination.sender, metadata.unspentFeeXlpRecipient);

    }

    function _withdrawUnspentFeeAndUnlockDeposit(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest
    ) internal {
        // Take the unspent fee from the first asset and send it to the xlp
        Asset memory firstAssetBase = voucherRequest.origination.assets[0];
        Asset memory feeAsset = Asset({
            erc20Token: firstAssetBase.erc20Token,
            amount: voucherRequest.origination.feeRule.unspentVoucherFee
        });
        feeAsset.transfer(metadata.unspentFeeXlpRecipient);
        // Send what's left to the sender
        uint256 amountAfterFee = _getAmountWithFeeAt(
            firstAssetBase.amount,
            uint256(metadata.core.createdAt),
            uint256(metadata.core.voucherIssuedAt),
            voucherRequest.origination.feeRule
        ) - voucherRequest.origination.feeRule.unspentVoucherFee;
        Asset memory senderPayout = Asset({
            erc20Token: firstAssetBase.erc20Token,
            amount: amountAfterFee
        });
        senderPayout.transfer(voucherRequest.origination.sender);
        // Return the rest of the assets to user
        for (uint256 i = 1; i < voucherRequest.origination.assets.length; i++) {
            Asset memory assetBase = voucherRequest.origination.assets[i];
            uint256 amountWithFee = _getAmountWithFeeAt(
                assetBase.amount,
                uint256(metadata.core.createdAt),
                uint256(metadata.core.voucherIssuedAt),
                voucherRequest.origination.feeRule
            );
            Asset memory refundAsset = Asset({erc20Token: assetBase.erc20Token, amount: amountWithFee});
            refundAsset.transfer(voucherRequest.origination.sender);
        }
    }

    function _secureOriginationAssets(AtomicSwapVoucherRequest calldata voucherRequest) internal {
        uint256 maxFee = voucherRequest.origination.feeRule.maxFeePercentNumerator;
        address sender = voucherRequest.origination.sender;
        for (uint256 i = 0; i < voucherRequest.origination.assets.length; i++) {
            Asset memory asset = voucherRequest.origination.assets[i];
            uint256 amountWithMaxFee = _getAmountWithFee(asset.amount, maxFee);
            Asset memory securedAsset = Asset({erc20Token: asset.erc20Token, amount: amountWithMaxFee});
            securedAsset.secure(sender);
        }
    }

    function _buildInitialMetadata() internal view returns (AtomicSwapMetadata memory metadata){
        metadata.core.status = AtomicSwapStatus.NEW;
        metadata.core.createdAt = uint40(block.timestamp);
        return metadata;
    }

    function _requireMatchingRequest(bytes32 requestId, AtomicSwapVoucherRequest calldata voucherRequest) internal pure {
        bytes32 computedReqId = voucherRequest.getVoucherRequestId();
        require(computedReqId == requestId, VoucherRequestIdMismatch(requestId, computedReqId));
    }

    function _assertAltVoucherTransition(
        VoucherType currentType,
        VoucherType nextType,
        bytes32 requestId
    ) internal pure {
        if (currentType == VoucherType.STANDARD) {
            require(nextType == VoucherType.ALT, InvalidVoucherType(requestId, VoucherType.ALT, nextType));
        } else if (currentType == VoucherType.OVERRIDE) {
            require(nextType == VoucherType.ALT_OVERRIDE, InvalidVoucherType(requestId, VoucherType.ALT_OVERRIDE, nextType));
        } else {
            revert InvalidVoucherType(requestId, VoucherType.STANDARD, currentType);
        }
    }

    function _assertOverrideVoucherTransition(
        VoucherType currentType,
        VoucherType nextType,
        bytes32 requestId
    ) internal pure {
        if (currentType == VoucherType.STANDARD) {
            require(nextType == VoucherType.OVERRIDE, InvalidVoucherType(requestId, VoucherType.OVERRIDE, nextType));
        } else if (currentType == VoucherType.ALT) {
            require(nextType == VoucherType.ALT_OVERRIDE, InvalidVoucherType(requestId, VoucherType.ALT_OVERRIDE, nextType));
        } else {
            revert InvalidVoucherType(requestId, VoucherType.OVERRIDE, currentType);
        }
    }

    function _bondPercentAmount(AtomicSwapMetadata storage metadata) internal view returns (uint256) {
        uint256 amountAfterFee = metadata.amountsAfterFee[0];
        return _getAmountWithBond(amountAfterFee) - amountAfterFee;
    }

    function _clearOverrideBond(AtomicSwapMetadata storage meta) internal {
        meta.overrideBondToken = address(0);
        meta.overrideBondAmount = 0;
    }

    function _clearDisputeBond(AtomicSwapMetadata storage meta) internal {
        meta.disputeBondToken = address(0);
        meta.disputeBondAmount = 0;
    }

    function _refundOverrideBond(AtomicSwapMetadata storage metadata) internal {
        uint256 overrideAmount = metadata.overrideBondAmount;
        if (overrideAmount == 0) {
            return;
        }
        _tokenIncrementDeposit(
            Asset({erc20Token: metadata.overrideBondToken, amount: overrideAmount}),
            metadata.core.voucherIssuerL2XlpAddress
        );
        _clearOverrideBond(metadata);
    }

    function _refundDisputeBondIfPosted(AtomicSwapMetadata storage metadata) internal {
        uint256 disputeAmount = metadata.disputeBondAmount;
        if (disputeAmount == 0) {
            return;
        }
        _tokenIncrementDeposit(
            Asset({erc20Token: metadata.disputeBondToken, amount: disputeAmount}),
            metadata.core.voucherIssuerL2XlpAddress
        );
        _clearDisputeBond(metadata);
    }

    function _verifyAllowedXlp(AtomicSwapVoucherRequest calldata voucherRequest, address xlp) internal view {
        (bool found, address l1XlpAddress) = registeredXlps.tryGet(xlp);
        require(found, XlpNotRegistered(xlp));
        for (uint256 i = 0; i < voucherRequest.origination.allowedXlps.length; i++) {
            if (l1XlpAddress == voucherRequest.origination.allowedXlps[i]) {
                return;
            }
        }
        revert XlpNotAllowed(voucherRequest.getVoucherRequestId(), voucherRequest.origination.allowedXlps, xlp);
    }

    function _getAmountWithFeeAt(uint256 amountIn, uint256 startTimestamp, uint256 endTimestamp, AtomicSwapFeeRule memory feeRule) internal pure returns (uint256) {
        uint256 elapsed = endTimestamp - startTimestamp;
        uint256 calculatedFee = feeRule.startFeePercentNumerator + elapsed * feeRule.feeIncreasePerSecond;
        if (calculatedFee > feeRule.maxFeePercentNumerator) {
            calculatedFee = feeRule.maxFeePercentNumerator;
        }
        return _getAmountWithFee(amountIn, calculatedFee);
    }


    function _processAtomicSwapFeeRefund(
        AtomicSwapMetadata storage metadata,
        AtomicSwapVoucherRequest calldata voucherRequest
    ) internal {
        delete metadata.amountsAfterFee;
        for (uint256 i = 0; i < voucherRequest.origination.assets.length; i++) {
            Asset memory baseAsset = voucherRequest.origination.assets[i];
            uint256 amountWithMaxFee = _getAmountWithFee(baseAsset.amount, voucherRequest.origination.feeRule.maxFeePercentNumerator);
            uint256 amountWithCurrentFee = _getAmountWithFeeAt(
                baseAsset.amount,
                uint256(metadata.core.createdAt),
                block.timestamp,
                voucherRequest.origination.feeRule
            );
            uint256 refund = amountWithMaxFee - amountWithCurrentFee;
            Asset memory refundAsset = Asset({erc20Token: baseAsset.erc20Token, amount: refund});
            refundAsset.transfer(voucherRequest.origination.sender);
            metadata.amountsAfterFee.push(amountWithCurrentFee);
        }
    }

    function _getAmountWithFee(uint256 amountIn, uint256 _fee) internal pure returns (uint256) {
        uint256 fee = amountIn * _fee / 10000;
        return amountIn + fee;
    }

    function _requireVoucherIssuedOrStaleDisputed(AtomicSwapMetadata storage metadata, bytes32 requestId) internal view returns (bool staleDispute) {
        AtomicSwapStatus status = metadata.core.status;

        if (status == AtomicSwapStatus.VOUCHER_ISSUED) {
            require(
                uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE <= block.timestamp,
                ActionTooSoon("voucher unlock", metadata.core.voucherIssuedAt, uint256(metadata.core.voucherIssuedAt) + TIME_TO_DISPUTE, block.timestamp)
            );
            return false;
        }

        if (status == AtomicSwapStatus.DISPUTE) {
            require(
                uint256(metadata.core.voucherIssuedAt) + TIME_BEFORE_DISPUTE_EXPIRES <= block.timestamp,
                ActionTooSoon("dispute unlock", metadata.core.voucherIssuedAt, uint256(metadata.core.voucherIssuedAt) + TIME_BEFORE_DISPUTE_EXPIRES, block.timestamp)
            );
            return true;
        }

        revert InvalidAtomicSwapStatus(requestId, AtomicSwapStatus.VOUCHER_ISSUED, status);
    }

    // Collect a bond from caller: either 10% of first asset-after-fee or 0.1 ETH
    // Returns (token, amount)
    function _computeBond(AtomicSwapMetadata storage metadata, AtomicSwapVoucherRequest calldata voucherRequest) internal view returns (address token, uint256 amount) {
        // First asset in the voucher request
        Asset memory firstAsset = voucherRequest.origination.assets[0];
        // 10% of first asset based on the amount after fee calculated on voucher issue
        uint256 bondPercentAmount = _bondPercentAmount(metadata);

        // Case 1: caller provides flat native bond
        if (msg.value > 0) {
            if (msg.value == FLAT_NATIVE_BOND) {
                return (NATIVE_ETH, msg.value);
            }
            // Case 2: first asset is native and caller provided exact 10% of first asset as native
            if (firstAsset.erc20Token == NATIVE_ETH && msg.value == bondPercentAmount) {
                return (NATIVE_ETH, msg.value);
            }
            revert AmountMismatch("bond", FLAT_NATIVE_BOND, msg.value);
        }

        // Case 3: first asset is ERC20 and caller provides 10% of first asset as tokens via allowance
        require(firstAsset.erc20Token != NATIVE_ETH, AmountMismatch("bond", bondPercentAmount, msg.value));
        return (firstAsset.erc20Token, bondPercentAmount);
    }

    function _collectOverrideBond(AtomicSwapMetadata storage metadata, AtomicSwapVoucherRequest calldata voucherRequest) internal {
        (address token, uint256 amount) = _computeBond(metadata, voucherRequest);
        // Secure funds from caller
        if (token == NATIVE_ETH) {
            Asset({erc20Token: NATIVE_ETH, amount: amount}).secure(msg.sender);
        } else {
            Asset memory firstAsset = Asset({
                erc20Token: voucherRequest.origination.assets[0].erc20Token,
                amount: amount
            });
            firstAsset.secure(msg.sender);
        }
        metadata.overrideBondToken = token;
        metadata.overrideBondAmount = amount;
    }

    function originDisputeModule() public view returns (address) {
        return _originDisputeModule;
    }

    function getOriginInsolvencyReportNonce(address reporter) external view returns (uint256) {
        return originInsolvencyReportNonces[reporter];
    }

    function isRequestInReport(bytes32 reportId, bytes32 requestId) public view returns (bool) {
        return originRequestInReport[reportId][requestId];
    }

    function disputeInsolventXlp(
        DisputeVoucher[] calldata _disputeVouchers,
        VoucherWithRequest[] calldata _altVouchers,
        address _l2XlpAddressToSlash,
        address payable _l1Beneficiary,
        uint256 _chunkIndex,
        uint256 _numberOfChunks,
        uint256 _nonce,
        bytes32 _committedRequestIdsHash,
        uint256 _committedVoucherCount
    ) external payable virtual override {
        (_disputeVouchers, _altVouchers, _l2XlpAddressToSlash, _l1Beneficiary, _chunkIndex, _numberOfChunks, _nonce, _committedRequestIdsHash, _committedVoucherCount);
        _delegateToOriginModule(msg.data);
    }

    function disputeVoucherOverride(
        DisputeVoucher[] calldata _disputeVouchers,
        address _l2XlpAddressToSlash,
        address payable _l1Beneficiary
    ) external payable virtual override {
        (_disputeVouchers, _l2XlpAddressToSlash, _l1Beneficiary);
        _delegateToOriginModule(msg.data);
    }

    function disputeXlpUnspentVoucherClaim(
        DisputeVoucher[] calldata _disputeVouchers,
        address payable _l1Beneficiary
    ) external payable virtual override {
        (_disputeVouchers, _l1Beneficiary);
        _delegateToOriginModule(msg.data);
    }

    function withdrawDisputeBonds(bytes32[] calldata _requestIds) external virtual override {
        (_requestIds);
        _delegateToOriginModule(msg.data);
    }

    function reportJustifiedDisputeRequests(bytes32 _reportId, bytes32[] calldata _requestIds) external virtual override {
        (_reportId, _requestIds);
        _delegateToOriginModule(msg.data);
    }

    function onXlpSlashedMessage(SlashOutput calldata _slashOutput) external virtual override {
        (_slashOutput);
        _delegateToOriginModule(msg.data);
    }

    function _delegateToOriginModule(bytes memory data) internal returns (bytes memory returndata) {
        address module = _originDisputeModule;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = module.delegatecall(data);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        return result;
    }

}
