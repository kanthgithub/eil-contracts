// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls

import "../IL1Bridge.sol";
import "./IArbOutbox.sol";
import "./IArbInbox.sol";
import "../../common/Errors.sol";
import "../common/EnvelopeLib.sol";

contract L1ArbitrumBridgeConnector is IL1Bridge {
    IArbOutbox public immutable outbox;
    IArbInbox public immutable inbox;
    address private _l2AppSender;
    constructor(IArbOutbox _outbox, IArbInbox _inbox) {
        outbox = _outbox;
        inbox = _inbox;
    }

    function sendMessageToL2(address _destination, bytes calldata _data, uint256 _gasLimit) external {
        // Verify envelope fromApp == msg.sender
        (, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        (address from, ) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        inbox.createRetryableTicket(
            _destination,
            0,
            2000000000,
            msg.sender,
            msg.sender,
            _gasLimit,
            1,
            _data
        );
    }

    function l2Sender() external view returns (address) {
        return outbox.l2ToL1Sender();
    }

    function l2AppSender() external view returns (address) {
        return _l2AppSender;
    }


    // Each bridge message is encoded as:
    // (bytes32[] proof, uint256 index, address l2Sender, address to, uint256 l2Block,
    //  uint256 l1Block, uint256 l2Timestamp, uint256 value, bytes data)
    function applyL2ToL1Messages(bytes[] calldata bridgeMessages) external returns (uint256 applied) {
        for (uint256 i = 0; i < bridgeMessages.length; i++) {
            (
                bytes32[] memory proof,
                uint256 index,
                address l2SenderAddress,
                address to,
                uint256 l2Block,
                uint256 l1Block,
                uint256 l2Timestamp,
                uint256 value,
                bytes memory data
            ) = abi.decode(bridgeMessages[i], (bytes32[], uint256, address, address, uint256, uint256, uint256, uint256, bytes));
            outbox.executeTransaction(
                proof,
                index,
                l2SenderAddress,
                to,
                l2Block,
                l1Block,
                l2Timestamp,
                value,
                data
            );
            applied++;
        }
    }

    function forwardFromL2(address to, bytes calldata data, uint256 gasLimit) external {
        (gasLimit);
        require(msg.sender == address(outbox), InvalidCaller("not L2 bridge", address(outbox), msg.sender));
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(data);
        address prev = _l2AppSender;
        _l2AppSender = appSender;
        (bool success, bytes memory reason) = to.call(inner);
        _l2AppSender = prev;
        require(success, ExternalCallReverted("L2->L1 forward", to, reason));
    }
}
