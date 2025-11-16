// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls

import "../IL2Bridge.sol";
import "./L2CrossDomainMessenger.sol";
import "../../common/Errors.sol";
import "../common/EnvelopeLib.sol";

contract L2OptimismBridgeConnector is IL2Bridge {
    IL2CrossDomainMessenger public immutable l2Messenger;
    address private _tmpL1Sender;
    address private _tmpL1AppSender;

    constructor(IL2CrossDomainMessenger _messenger) {
        l2Messenger = _messenger;
    }

    function l1Sender() external view returns (address) {
        return _tmpL1Sender;
    }

    function l1AppSender() external view returns (address) {
        return _tmpL1AppSender;
    }


    function sendMessageToL1(address _destination, bytes calldata _data, uint256 _gasLimit) external returns (uint256) {
        // Gate by envelope fromApp == msg.sender
        (, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        (address from, ) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        l2Messenger.sendMessage(_destination, _data, uint32(_gasLimit));
        return 0;
    }

    /// @notice Forward an L1->L2 message to the provided destination (ignored here; paymasterTarget is used), capturing the true L1 sender from the messenger.
    /// @dev Must be called by the canonical L2 messenger; sets l1Sender() context only during this call.
    function forwardFromL1(address to, bytes calldata data, uint256 gasLimit) external {
        require(msg.sender == address(l2Messenger), InvalidCaller("not L2 messenger", address(l2Messenger), msg.sender));
        address prev = _tmpL1Sender;
        _tmpL1Sender = l2Messenger.xDomainMessageSender();
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(data);
        address prevApp = _tmpL1AppSender;
        _tmpL1AppSender = appSender;
        (bool success, bytes memory reason) = to.call{gas: gasLimit}(inner);
        _tmpL1AppSender = prevApp;
        _tmpL1Sender = prev;
        require(success, ExternalCallReverted("L1->L2 forward", to, reason));
    }

}
