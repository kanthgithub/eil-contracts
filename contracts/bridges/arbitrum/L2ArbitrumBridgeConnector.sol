// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls

import "./ArbSys.sol";
import "../IL2Bridge.sol";
import "../../common/Errors.sol";
import "../common/EnvelopeLib.sol";

contract L2ArbitrumBridgeConnector is IL2Bridge {
    address private _tmpL1Sender;
    address private _tmpL1AppSender;

    function l1Sender() external view returns (address) {
        return _tmpL1Sender;
    }

    function l1AppSender() external view returns (address) {return _tmpL1AppSender;}

    function sendMessageToL1(address _destination, bytes calldata _data, uint256) external returns (uint256) {
        // Gate by verifying the provided wrapper encodes an app-level sender equal to msg.sender
        (, bytes memory envelope,) = EnvelopeLib.decodeWrapper(_data);
        (address from,) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        // ticketId tracks the L1 message.
        uint256 ticketId = ArbSys(address(100)).sendTxToL1(_destination, _data);
        return ticketId;
    }

    /// @notice Forward an L1->L2 message to a target, capturing the true L1 sender from Arbitrum precompile.
    /// @dev On Arbitrum, L1 originating calls arrive with address aliasing; the canonical L1 sender is exposed by ArbSys.
    function forwardFromL1(address to, bytes calldata data, uint256 gasLimit) external {
        (gasLimit);
        address prev = _tmpL1Sender;
        address sender = ArbSys(address(100)).arbTxL1Sender();
        // When not called from an L1 origin, sender may be zero; protect by requiring non-zero to mitigate misuse.
        require(sender != address(0), InvalidCaller("not L1-originated", address(0), msg.sender));
        _tmpL1Sender = sender;
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(data);
        address prevApp = _tmpL1AppSender;
        _tmpL1AppSender = appSender;
        (bool success, bytes memory reason) = to.call(inner);
        _tmpL1AppSender = prevApp;
        _tmpL1Sender = prev;
        require(success, ExternalCallReverted("L1->L2 forward", to, reason));
    }

}
