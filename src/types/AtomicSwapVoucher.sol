// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Asset.sol";
import "./DestinationSwapComponent.sol";
import "./Enums.sol";
/**
 * @notice The structure representing the Xlp side of the Atomic Swap.
 * This structure is signed by a Xlp entity and submitted on the origination chain.
 * The submission of this signature starts the countdown process allowing the Xlp to withdraw the funds.
 * This structure is submitted on the destination chain to release the requested assets.
 * If the Xlp has sufficient balance the atomic swap is completed.
 * Otherwise the atomic swap is cancelled and the dispute process is started.
 */
struct AtomicSwapVoucher {
    bytes32 requestId;
    address payable originationXlpAddress;
    DestinationSwapComponent voucherRequestDest;
    uint256 expiresAt;
    VoucherType voucherType;
    /// @notice The Xlp's signature over the AtomicSwapVoucher struct.
    bytes xlpSignature;
}
