// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls

import "../IL1Bridge.sol";
import "./L1CrossDomainMessenger.sol";
import "./IOptimismPortal.sol";
import "../../common/Errors.sol";
import "../common/EnvelopeLib.sol";

contract L1OptimismBridgeConnector is IL1Bridge {
    IL1CrossDomainMessenger public immutable l1Messenger;
    IOptimismPortal public immutable portal;
    // Transient app-sender captured from envelope during forwardFromL2
    address private _l2AppSender;
    constructor(IL1CrossDomainMessenger _messenger, IOptimismPortal _portal) {
        l1Messenger = _messenger;
        portal = _portal;
    }

    function l2Sender() external view returns (address) {
        return l1Messenger.xDomainMessageSender();
    }

    function l2AppSender() external view returns (address) {
        return _l2AppSender;
    }


    function sendMessageToL2(address _destination, bytes calldata _data, uint256 _gasLimit) external {
        // Verify envelope fromApp == msg.sender
        (, bytes memory envelope, ) = EnvelopeLib.decodeWrapper(_data);
        (address from, ) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        l1Messenger.sendMessage(_destination, _data, uint32(_gasLimit));
    }

    // Each bridge message is encoded as: (WithdrawalTransaction wd, bytes proof)
    function applyL2ToL1Messages(bytes[] calldata bridgeMessages) external returns (uint256 applied) {
        for (uint256 i = 0; i < bridgeMessages.length; i++) {
            (IOptimismPortal.WithdrawalTransaction memory wd, bytes memory proof) = abi.decode(bridgeMessages[i], (IOptimismPortal.WithdrawalTransaction, bytes));
            portal.finalizeWithdrawalTransaction(wd, proof);
            applied++;
        }
    }

    function forwardFromL2(address to, bytes calldata data, uint256 gasLimit) external {
        (gasLimit);
        require(msg.sender == address(l1Messenger), InvalidCaller("not L2 bridge", address(l1Messenger), msg.sender));
        // Envelope: (address appSender, bytes inner)
        (address appSender, bytes memory inner) = abi.decode(data, (address, bytes));
        address prev = _l2AppSender;
        _l2AppSender = appSender;
        (bool success, bytes memory reason) = to.call(inner);
        _l2AppSender = prev;
        require(success, ExternalCallReverted("L2->L1 forward", to, reason));
    }
}
