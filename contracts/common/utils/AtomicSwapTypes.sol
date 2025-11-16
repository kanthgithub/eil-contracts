// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../structs/DestinationVoucherRequestsData.sol";
import "../structs/SessionData.sol";
import "../../types/AtomicSwapVoucher.sol";
import "../../types/AtomicSwapVoucherRequest.sol";
import "../../types/DestinationSwapComponent.sol";
import "../../types/Enums.sol";

/**
 * @dev Off chain use only.
 * A helper interface to make abi.encode() of compound types easier.
 */
interface AtomicSwapTypes {
    function getVoucherRequest(
        AtomicSwapVoucherRequest calldata voucherRequest
    ) external;

    function getVouchers(
        AtomicSwapVoucher[] calldata vouchers,
        SessionData calldata sessionData
    ) external;

    function getVouchersForEphemeralSigning(
        AtomicSwapVoucher[] calldata vouchers,
        bytes calldata ephemeralSignature
    ) external;

    function getVoucherRequests(
        DestinationVoucherRequestsData calldata voucherRequestsData
    ) external;

    function getDataForVoucherSignature(
        DestinationSwapComponent calldata destinationComponent,
        bytes32 requestId,
        address originationXlpAddress,
        uint256 expiresAt,
        VoucherType voucherType
    ) external;
}
