// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * EnvelopeLib — neutral cross-connector payload helpers
 *
 * Overview
 * - Two layers of payload are used to keep connectors target-agnostic while preserving strong app identity.
 *
 * Layers
 * - Inner (bytes): The ABI-encoded function call to execute at the destination application.
 * - Envelope (bytes): abi.encode(address appSender, bytes inner)
 *     appSender = the L1/L2 application initiating the message (e.g., Paymaster or StakeManager)
 *     inner     = the ABI-encoded call to be performed on the destination application
 *   Connectors use the envelope to verify authenticity at send-time (from == msg.sender) and to set
 *   transient l1AppSender/l2AppSender context at delivery-time.
 * - Forward Wrapper (bytes): abi.encodeCall(forwardFrom{Side}, (address to, bytes envelope, uint256 gasLimit))
 *     to       = destination contract (connectors do not store targets)
 *     envelope = the application envelope described above
 *     gasLimit = the gas hint used by the remote connector when executing the call
 *
 * Flow:
 * 1) Origin app builds inner → envelope → wrapper and calls its local connector sendMessageToL1/L2.
 * 2) Local connector decodes wrapper → envelope and requires(envelope.appSender == msg.sender).
 * 3) Destination connector receives forwardFrom{OtherSide}(to, envelope, gas), decodes the envelope,
 *    sets transient app-sender context, and invokes to.call(inner).
 * 4) Destination app enforces msg.sender and connector-reported sender contexts.
 */
library EnvelopeLib {
    /// Decode a forward wrapper produced by abi.encodeCall(forwardFrom{Side}, (to, envelope, gas)).
    function decodeWrapper(bytes calldata data) internal pure returns (address to, bytes memory envelope, uint256 gasLimit) {
        // Skip 4-byte selector when created via abi.encodeCall.
        return abi.decode(data[4:], (address, bytes, uint256));
    }

    /// Decode an application envelope into the app-level sender and the inner call data.
    function decodeEnvelope(bytes memory envelope) internal pure returns (address appSender, bytes memory inner) {
        return abi.decode(envelope, (address, bytes));
    }
}
