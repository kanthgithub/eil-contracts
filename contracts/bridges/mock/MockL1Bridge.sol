// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../IL1Bridge.sol";
import "../common/EnvelopeLib.sol";
import "../../common/Errors.sol";

contract MockL1Bridge is IL1Bridge {

    uint256 public immutable l2ChainId;
    address private _l2Sender;
    address private _l2AppSender;
    event MockMessageSentToL2(uint256 chainId, address sender, address destination, bytes data, uint256 gasLimit);

    constructor(uint256 _l2ChainId) {
        l2ChainId = _l2ChainId;
    }

    function l2Sender() external view returns (address) {
        return _l2Sender;
    }

    function l2AppSender() external view returns (address) {
        return _l2AppSender;
    }

    function sendMessageToL2(address _destination, bytes calldata _data, uint256 _gasLimit) external override {
        (, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        (address from, ) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        emit MockMessageSentToL2(l2ChainId, msg.sender, _destination, _data, _gasLimit);
    }

    function applyL2ToL1Messages(bytes[] calldata /* bridgeMessages */) external pure returns (uint256) {
        return 0;
    }

    function forwardFromL2(address destination, bytes calldata data, uint256 /* gasLimit */) external {
        _forwardFromL2(destination, data, msg.sender);
    }

    error ErrorMessageFromL2(uint256 l2ChainId, address sender, bytes data, bytes result);

    function debugOnMessageFromL2(address _sender, address /*destination*/, bytes calldata _data) external {
        (address to, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        // destination is connector supplied during send; actual target encoded in wrapper.
        _forwardFromL2(to, envelope, _sender);
    }

    function _forwardFromL2(address destination, bytes memory envelope, address sender) private {
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(envelope);
        address previousSender = _l2Sender;
        address previousAppSender = _l2AppSender;
        _l2Sender = sender;
        _l2AppSender = appSender;
        //solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = destination.call(inner);
        _l2Sender = previousSender;
        _l2AppSender = previousAppSender;
        require(success, ErrorMessageFromL2(l2ChainId, sender, inner, result));
    }
}
