// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/Enums.sol";
import "../types/AtomicSwapVoucherRequest.sol";
import "../types/AtomicSwapVoucher.sol";
import "../types/AtomicSwapMetadata.sol";
/**
 * @title IOriginSwapManager
 * @notice Interface defining the core functionality for managing atomic swaps between chains.
 * @notice Handles the creation, signing, execution and cancellation of cross-chain atomic swaps.
 */
struct VoucherWithRequest {
    AtomicSwapVoucherRequest voucherRequest;
    AtomicSwapVoucher voucher;
}

interface IOriginSwapManager {

    event VoucherRequestCreated(bytes32 indexed id, address indexed sender, AtomicSwapVoucherRequest voucherRequest);
    event VoucherIssued(
        bytes32 indexed id,
        address indexed sender,
        uint256 indexed senderNonce,
        AtomicSwapVoucher voucher
    );
    event UserDepositWithdrawn(bytes32 indexed requestId, address indexed sender, address indexed voucherIssuer);
    event VoucherRequestCancelled(bytes32 indexed requestId, address indexed sender);
    event UnspentVoucherFeeClaimed(bytes32 indexed requestId, address indexed sender, address indexed withdrawer, address voucherIssuer);
    event UnspentVoucherFeeWithdrawn(bytes32 indexed requestId, address indexed sender, address indexed withdrawer);

    /**
     * @notice View function to inspect stored metadata for an existing atomic swap.
     * @param requestId - identifier of the voucher request.
     * @return metadata - current metadata tracked on L2.
     */
    function getAtomicSwapMetadata(bytes32 requestId) external view returns (AtomicSwapMetadata memory metadata);

    /**
     * @notice View function to get the current nonce of a specific sender address.
     * @param sender - the address of the sender whose nonce is being queried.
     * @return uint256 - the current nonce value for the specified sender address.
     */
    function getSenderNonce(address sender) external view returns (uint256);

    /**
     * @notice View function to get the timestamp when a specific xlp made an override of an atomic swap voucher.
     * @notice This timestamp is typically used to determine eligibility for withdrawal after a timelock.
     * @notice Making a fraudulent override is will be penalized.
     * @param requestId The unique identifier of the voucher request.
     * @param l2XlpAddress The address of the xlp whose override timestamp is being queried.
     * @return uint256 The block timestamp when the specified xlp made an override of the an atomic swap voucher.
     */
    function getVoucherOverrideTimestamp(bytes32 requestId, address l2XlpAddress) external view returns (uint256);

    /**
     * @notice Called by the user on the origin chain to provide funds and initiate the swap.
     * @param voucherRequest - the details of the current voucher request.
     */
    function lockUserDeposit(AtomicSwapVoucherRequest calldata voucherRequest) external payable;

    /**
     * @notice Called by the xlp on the origin chain to advertise the voucher signature.
     * @notice The signature provided by the xlp is also an authorization for the user to withdraw funds on the destination chain
     * @notice Multiple xlps can legitimately call this method simultaneously to propose their liquidity to users.
     * @param vouchers - vouchers with their corresponding requests.
     */
    function issueVouchers(VoucherWithRequest[] calldata vouchers) external;

    /**
     * @notice Called by a xlp to issue alternative vouchers during a dispute.
     * @notice Valid only when the swap is under DISPUTE; enforces STANDARD->ALT or OVERRIDE->ALT_OVERRIDE.
     * @param vouchers - details of the alternative vouchers.
     */
    function issueAltVouchers(VoucherWithRequest[] calldata vouchers) external;

    /**
     * @notice Called by the xlp on the origin chain to assert this xlp has provided liquidity.
     * @notice This step replaces the stored liquidity provider with the caller.
     * @notice Only the xlp whose liquidity was used on the destination chain can legitimately call this function.
     * @notice Xlps that falsely asserts their liquidity was used on the destination chain will be penalized.
     * @param voucherOverride - details of the voucher that overrides the one previously accepted.
     */
    function overrideVoucher(AtomicSwapVoucherRequest calldata voucherRequest, AtomicSwapVoucher calldata voucherOverride) external payable;

    /**
     * @notice Called by the xlp on the origin chain to retrieve user funds.
     * @param voucherRequests - requests whose funds should be withdrawn.
     */
    function withdrawFromUserDeposit(AtomicSwapVoucherRequest[] calldata voucherRequests) external;

    /**
     * @notice Called by the user on the origin chain to cancel the swap and retrieve user funds.
     * @param voucherRequest - identifier of the voucher request.
     */
    function cancelVoucherRequest(AtomicSwapVoucherRequest calldata voucherRequest) external;

    /**
     * @notice Called by any xlp on the origin chain to lock the unspent voucher fee until it can be withdrawn, after the dispute window.
     * @param voucherRequest - identifier of the voucher request.
     */
    function claimUnspentVoucherFee(AtomicSwapVoucherRequest calldata voucherRequest) external;

    /**
     * @notice Called by the xlp on the origin chain to withdraw the unspent voucher fee after the dispute window.
     * @param voucherRequest - identifier of the voucher request.
     */
    function withdrawUnspentVoucherFee(AtomicSwapVoucherRequest calldata voucherRequest) external;
}
