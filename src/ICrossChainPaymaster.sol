// SPDX-License-Identifier: MIT
/* solhint-disable func-name-mixedcase */
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/BasePaymaster.sol";

import "./common/Errors.sol";
import "./common/structs/SessionData.sol";
import "./common/utils/AtomicSwapTypes.sol";
import "./interfaces/IDestinationSwapManager.sol";
import "./interfaces/IL2XlpDisputeManager.sol";
import "./interfaces/IL2XlpPenalizer.sol";
import "./interfaces/IL2XlpRegistry.sol";
import "./interfaces/IOriginSwapManager.sol";
import "./interfaces/ITokenDepositManager.sol";
import "./types/Enums.sol";

/// @notice A helper abstract contract that exposes the full interface of the CrossChainPaymaster.
/// @notice This contract is never implemented and is only used to type-safe code using Viem or Alloy.
abstract contract ICrossChainPaymaster is BasePaymaster,
                                          AtomicSwapTypes,
                                          ITokenDepositManager,
                                          IOriginSwapManager,
                                          IL2XlpDisputeManager,
                                          IL2XlpRegistry,
                                          IL2XlpPenalizer,
                                          IDestinationSwapManager
{
    uint256 public immutable POST_OP_GAS_COST;
    uint256 public immutable L1_SLASH_GAS_LIMIT;
    uint256 public immutable L1_DISPUTE_GAS_LIMIT;

    function l1Connector() external view virtual returns (address);

    function l2Connector() external view virtual returns (address);

    function l1StakeManager() external view virtual returns (address);

    function TIME_TO_DISPUTE() external view virtual returns (uint256);

    function USER_CANCELLATION_DELAY() external view virtual returns (uint256);

    function FLAT_NATIVE_BOND() external view virtual returns (uint256);

    function TIME_BEFORE_DISPUTE_EXPIRES() external view virtual returns (uint256);

    function VOUCHER_MIN_EXPIRATION_TIME() external view virtual returns (uint256);

    function DISPUTE_BOND_PERCENT() external view virtual returns (uint256);

    function getOriginInsolvencyReportNonce(address reporter) external view virtual returns (uint256);

    function getDestinationInsolvencyReportNonce(address reporter) external view virtual returns (uint256);

    function isRequestInReport(bytes32 reportId, bytes32 requestId) external view virtual returns (bool);

     function getHashForEphemeralSignature(
        AtomicSwapVoucher[] memory vouchers,
        SessionData memory sessionData
    ) public virtual returns(bytes32);

    function getSessionData() external view virtual returns (SessionData memory);

    /**
     * if paymaster validation fails on ephemeral signature, the context field would return this error
     * @param ephemeralSigner ephemeral signer from the voucher request
     */
    error EphemeralSignatureInvalid(address ephemeralSigner);

    /**
     * if paymaster validation fails on voucher signature, the context field would return this error
     * @param index the index of the voucher that failed validation
     */
    error VoucherSignatureError(uint256 index);

    /// @dev Enumerate all errors from the Errors.sol into the generated ABI file.
    function touchErrors() external pure {

        address addr = address(0);
        Asset memory asset;
        Asset[] memory assets;

        require(false, VoucherRequestIdMismatch(0, 0));
        require(false, InvalidVoucherType(0, VoucherType.STANDARD, VoucherType.STANDARD));
        require(false, MsgSenderNotAllowedToPenalize(0, addr, addr, false));
        require(false, InvalidAccusationVoucherNotPaid(0, addr));
        require(false, InvalidAccusationXlpPaid(0, addr));
        require(false, VoucherRequestIdMismatch(0, 0));
        require(false, MsgSenderNotAllowedToPenalize(0, addr, addr, false));
        require(false, InvalidAccusationXlpHasSufficientBalance(0, addr, assets));
        require(false, XlpNotRegistered(addr));
        require(false, VoucherExpired(0, 0, 0));
        require(false, VoucherExpiresTooSoon(0, 0, 0));
        require(false, PaymasterSignatureMissing(""));
        require(false, NonceMismatch(0, 0));
        require(false, InsufficientMaxUserOpCost(0, 0));
        require(false, AddressMismatch(addr, addr));
        require(false, TransferExceedsBalance(addr, addr, 0, asset));
        require(false, XlpNotFound(addr));
        require(false, XlpNotAllowed(0, new address[](0), addr));
        require(false, UnspentClaimNotFound(0));
        require(false, UnspentFeeAlreadyClaimed(bytes32(0), addr));
        require(false, InvalidOrdering(""));
        require(false, AmountMismatch("", 0, 0));
        require(false, VouchersAndMinimumsIncompatible(0,0));
        require(false, VoucherAssetsAndMinimumsIncompatible(0,0));
        require(false, InvalidLength("", 0, 0));
        require(false, ActionTooLate("", 0, 0, 0));
        require(false, ActionTooSoon("", 0, 0, 0));
        require(false, VoucherRequestExpired(0, 0, 0));
        require(false, InvalidChunkIndex(0, 0));
        require(false, InvalidChunkCount(0, 0));
        require(false, InvalidReportId(bytes32(0), bytes32(0)));
        require(false, InvalidReportNonce(0, 0));
        require(false, DisputeNotJustified(bytes32(0)));
        require(false, RequestNotPartOfReport(bytes32(0), bytes32(0)));
        require(false, UnknownRequestId(bytes32(0)));
        require(false, ChunkSubmittedBeforeLastVoucher(0, 0));
        require(false, DisputeCommitmentMismatch(bytes32(0), bytes32(0)));
	    require(false, SignerAddressMismatch(address(0)));
        require(false, InvalidCaller("", address(0), address(0)));
        require(false, SessionDataNotFound(bytes32(0)));
        require(false, InvalidSwapStatus(bytes32(0), AtomicSwapStatus.NONE, AtomicSwapStatus.NONE));
        require(false, ChainIdMismatch(0, 0));
        require(false, InvalidAtomicSwapStatus(bytes32(0), AtomicSwapStatus.NONE, AtomicSwapStatus.NONE));
    }
}
