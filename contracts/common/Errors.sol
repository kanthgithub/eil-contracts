// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/Enums.sol";
import "../types/Asset.sol";

error NotSupported(string description);

error InvalidSwapStatus(bytes32 id, AtomicSwapStatus status, AtomicSwapStatus expectedStatus);

error AddressMismatch(address expected, address actual);

error SignerAddressMismatch(address expected);

error PaymasterSignatureMissing(bytes signature);

error InsufficientMaxUserOpCost(uint256 actualMaxCost, uint256 voucherMaxCost);

error SessionDataNotFound(bytes32 userOpHash);

error InsufficientBalance(address owner, uint256 balance, uint256 amount);

error UserOpHashMismatch(bytes32 expected, bytes32 actual);

error VoucherRequestIdMismatch(bytes32 expected, bytes32 actual);

error ChainAlreadyAdded(address l1XlpAddress, uint256 chainId, address paymaster, address l1Connector);

error ChainLimitReached(address l1XlpAddress, uint256 limit, uint256 attempted);

error InvalidAccusationVoucherNotPaid(bytes32 requestId, address l2XlpAddressToSlash);

error InvalidAccusationXlpPaid(bytes32 requestId, address l2XlpAddressToSlash);

error InvalidAccusationXlpHasSufficientBalance(bytes32 requestId, address l2XlpAddressToSlash, Asset[] assetsRequired);


error NoStake(address l1XlpAddress);

error NoLockedStake(address l1XlpAddress, uint256 amount, uint256 withdrawalTime);

error StakeAlreadyUnlocked(address l1XlpAddress, uint256 amountSlashed, uint256 withdrawalTime);

error StakeNotUnlocked(address l1XlpAddress, uint256 amount);

error StakeWithdrawalNotDue(address l1XlpAddress, uint256 withdrawalTime, uint256 blockTimestamp);

error ExternalCallReverted(string description, address destination, bytes revertReason);

error InvalidCaller(string description, address expected, address actual);

error InvalidAtomicSwapStatus(bytes32 requestId, AtomicSwapStatus allowed, AtomicSwapStatus actual);

error ChainIdMismatch(uint256 expected, uint256 actual);

error NonceMismatch(uint256 expected, uint256 actual);

error AmountMismatch(string description, uint256 expected, uint256 actual);

error InvalidOrdering(string description);

error InvalidVoucherType(bytes32 requestId, VoucherType expected, VoucherType actual);

error VoucherExpired(bytes32 requestId, uint256 expiresAt, uint256 blockTimestamp);

error VoucherExpiresTooSoon(bytes32 requestId, uint256 expiresAt, uint256 blockTimestamp);

error VoucherRequestExpired(bytes32 requestId, uint256 expiresAt, uint256 blockTimestamp);

error ActionTooSoon(string description, uint256 startActionWindow, uint256 endActionWindow, uint256 blockTimestamp);

error ActionTooLate(string description, uint256 startActionWindow, uint256 endActionWindow, uint256 blockTimestamp);

error XlpNotAllowed(bytes32 requestId, address[] allowedXlps, address proposedXlp);

error XlpNotRegistered(address xlp);

error XlpNotFound(address xlp);

error UnspentClaimNotFound(bytes32 requestId);

error UnspentFeeAlreadyClaimed(bytes32 requestId, address claimer);

error MsgSenderNotAllowedToPenalize(bytes32 requestId, address msgSender, address voucherRequestSender, bool isRegisteredXlp);

error TransferExceedsBalance(address from, address to, uint256 balance, Asset asset);

error NothingToClaim(string description, DisputeType disputeType, bytes32 id);

error InvalidLength(string description, uint256 expected, uint256 actual);

error VouchersAndMinimumsIncompatible(uint256 vouchersLength, uint256 minimumsLength);

error VoucherAssetsAndMinimumsIncompatible(uint256 vouchersLength, uint256 minimumsLength);

error TokensAndAmountsIncompatible(uint256 tokensLength, uint256 amountsLength);

error InvalidSlashShareRole(SlashShareRole maxRole, uint8 providedRole);

error InvalidChunkIndex(uint256 expected, uint256 actual);

error InvalidChunkCount(uint256 expected, uint256 actual);

error InvalidReportId(bytes32 expected, bytes32 actual);

error InvalidReportNonce(uint256 expected, uint256 actual);

error DisputeNotJustified(bytes32 reportId);

error RequestNotPartOfReport(bytes32 reportId, bytes32 requestId);

error InvalidDisputeType(string description, DisputeType expected, DisputeType actual);

error UnknownRequestId(bytes32 requestId);

error ChunkSubmittedBeforeLastVoucher(uint256 lastVoucherIssuedAt, uint256 firstChunkTimestamp);

error DisputeCommitmentMismatch(bytes32 expectedRequestIdsHash, bytes32 actualRequestIdsHash);
