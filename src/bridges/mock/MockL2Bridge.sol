// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../IL2Bridge.sol";
import "../common/EnvelopeLib.sol";
import "../../common/Errors.sol";

contract MockL2Bridge is IL2Bridge {

    address private _l1Sender;
    address private _l1AppSender;
    event MessageSentToL1(uint256 fromChain, address sender, address destination, bytes data, uint256 gasLimit);

    function l1Sender() external view returns (address) {
        return _l1Sender;
    }

    function l1AppSender() external view returns (address) {
        return _l1AppSender;
    }

    function sendMessageToL1(address _destination, bytes calldata _data, uint256 _gasLimit) external returns (uint256) {
        (, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        (address from, ) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        emit MessageSentToL1(block.chainid, msg.sender, _destination, _data, _gasLimit);
        return 0;
    }

    function forwardFromL1(address destination, bytes calldata data, uint256 /* gasLimit */) external {
        _forwardFromL1(destination, data, msg.sender);
    }

    error ErrorMessageFromL1(uint256 l2ChainId, address sender, address destination, bytes data, bytes result);

    function debugOnMessageFromL1(address _sender, address /*destination*/, bytes calldata _data) external {
        (address to, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        // destination is the connector passed in sendMessageToL1; actual target lives inside envelope.
        _forwardFromL1(to, envelope, _sender);
    }

    function _forwardFromL1(address destination, bytes memory envelope, address sender) private {
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(envelope);
        address previousSender = _l1Sender;
        address previousAppSender = _l1AppSender;
        _l1Sender = sender;
        _l1AppSender = appSender;
        //solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = destination.call(inner);
        _l1Sender = previousSender;
        _l1AppSender = previousAppSender;
        require(success, ErrorMessageFromL1(block.chainid, sender, destination, inner, result));
    }
}
