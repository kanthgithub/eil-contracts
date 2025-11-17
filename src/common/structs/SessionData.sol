// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @notice The structure representing the session data provided and signed by the user's ephemeral key.
 * This structure is signed by an ephemeral signer provided by the User in the PaymasterData.
 * This structure is submitted on the destination chain together with all the Voucher objects.
 * It is the Account's responsibility to decode, parse and validate this data.
 */
struct SessionData {
    /// @notice An arbitrary data that can be supplied by the user and co-signed by the user's ephemeral key.
    /// @notice This field can be used by users to pass arbitrary messages across chains.
    bytes data;
    /// @notice The signature over the session data made with the ephemeral key specified in the DestinationVoucherRequestsData.
    bytes ephemeralSignature;
}
