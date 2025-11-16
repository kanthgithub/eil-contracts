// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls

import "../IL1Bridge.sol";
import "../IL2Bridge.sol";
import "../common/EnvelopeLib.sol";
import "../../common/Errors.sol";

/// @notice Local L1 connector implementing both sides of the neutral bridge interfaces for L1-only messaging.
/// @notice Used in production on L1 to allow Paymaster <-> StakeManager communication without app-specific coupling.
contract L1EthereumLocalBridge is IL1Bridge, IL2Bridge {
    address private transient _tmpSender;
    address private transient _tmpL1AppSender;
    address private transient _tmpL2AppSender;

    /// @inheritdoc IL2Bridge
    function l1Sender() external view returns (address) {
        return _tmpSender;
    }

    function l1AppSender() external view returns (address) {return _tmpL1AppSender;}

    /// @inheritdoc IL1Bridge
    function l2Sender() external view returns (address) {
        return _tmpSender;
    }

    function l2AppSender() external view returns (address) {return _tmpL2AppSender;}

    /// @inheritdoc IL2Bridge
    function sendMessageToL1(
        address _destination,
        bytes calldata _data,
        uint256 _gasLimit
    )
    external
    returns (uint256) {
        // For local L2->L1, make L1 see l2Sender == connector (address(this))
        address prev = _tmpSender;
        _tmpSender = address(this);
        (bool success, bytes memory reason) = _destination.call{gas: _gasLimit}(_data);
        _tmpSender = prev;
        require(success, ExternalCallReverted("send L2->L1 local", _destination, reason));
        return 1;
    }

    /// @inheritdoc IL1Bridge
    function sendMessageToL2(address _destination, bytes calldata _data, uint256 _gasLimit) external {
        // For local L1->L2, make L2 see l1Sender == connector (address(this))
        address prev = _tmpSender;
        _tmpSender = address(this);
        // Gate by verifying envelope fromApp==msg.sender
        (, bytes memory envelope,) = EnvelopeLib.decodeWrapper(_data);
        (address from,) = EnvelopeLib.decodeEnvelope(envelope);
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        (bool success, bytes memory reason) = _destination.call{gas: _gasLimit}(_data);
        _tmpSender = prev;
        require(success, ExternalCallReverted("send L1->L2 local", _destination, reason));
    }

    // For the local bridge, each message is encoded as: (address to, bytes data, uint256 gasLimit, address l2Sender)
    function applyL2ToL1Messages(bytes[] calldata bridgeMessages) external returns (uint256 applied) {
        for (uint256 i = 0; i < bridgeMessages.length; i++) {
            (address to, bytes memory data, uint256 gasLimit, address l2SenderAddr) =
                                abi.decode(bridgeMessages[i], (address, bytes, uint256, address));
            address previousSender = _tmpSender;
            _tmpSender = l2SenderAddr;
            (bool success, bytes memory revertReason) = to.call{gas: gasLimit}(data);
            require(success, ExternalCallReverted("apply L2->L1 message", to, revertReason));
            _tmpSender = previousSender;
            applied++;
        }
    }

    event ForwardedFromL1(address indexed to, bytes data, uint256 gasLimit);

    function forwardFromL1(address to, bytes calldata data, uint256 gasLimit) external {
        (gasLimit);
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(data);
        address prev = _tmpL1AppSender;
        _tmpL1AppSender = appSender;
        (bool success, bytes memory reason) = to.call(inner);
        require(success, ExternalCallReverted("forward L1->L2 local", to, reason));
        _tmpL1AppSender = prev;
        emit ForwardedFromL1(to, data, gasLimit);
    }

    function forwardFromL2(address to, bytes calldata data, uint256 gasLimit) external {
        (gasLimit);
        address prev = _tmpSender;
        _tmpSender = address(this);
        (address appSender, bytes memory inner) = EnvelopeLib.decodeEnvelope(data);
        address prevApp = _tmpL2AppSender;
        _tmpL2AppSender = appSender;
        (bool success, bytes memory reason) = to.call(inner);
        require(success, ExternalCallReverted("L2->L1 forward local", to, reason));
        _tmpSender = prev;
        _tmpL2AppSender = prevApp;
        emit ForwardedFromL2(to, data, gasLimit);
    }

    event ForwardedFromL2(address indexed to, bytes data, uint256 gasLimit);
}
