// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls

import "../bridges/IL1Bridge.sol";
import "../bridges/IL2Bridge.sol";
import "../common/Errors.sol";

contract TestBridge is IL1Bridge, IL2Bridge{

    address private _l1Sender;
    address private _l2Sender;
    address private _l1AppSender;
    address private _l2AppSender;

    bool public revertOnMessageFailure;
    bool public queueL1ToL2; // if true, L1->L2 messages are queued and require pull to apply

    event MessageSentToL1FromBridge(address indexed to, bytes data, uint256 gasLimit);
    event MessageSentToL2FromBridge(address indexed to, bytes data, uint256 gasLimit);
    event MessageQueuedToL2(address indexed to, bytes data, uint256 gasLimit, bytes32 id);
    event ForwardedFromL2(address indexed to, bytes data, uint256 gasLimit);

    struct L2ToL1Message {
        bytes32 id;
        address to;
        bytes data;
        uint256 gasLimit;
        address l2SenderSaved;
        bool pending;
    }

    mapping(bytes32 id => L2ToL1Message msg) private l2ToL1Messages;
    bytes32[] private l2ToL1Ids;
    uint256 private l2ToL1Nonce;

    // Symmetric queue for L1 -> L2 when testing pull mode
    struct L1ToL2Message {
        bytes32 id;
        address to;
        bytes data;
        uint256 gasLimit;
        address l1SenderSaved;
        bool pending;
    }
    mapping(bytes32 id => L1ToL2Message msg) private l1ToL2Messages;
    bytes32[] private l1ToL2Ids;
    uint256 private l1ToL2Nonce;

    function l1Sender() external view returns (address) {
        return _l1Sender;
    }
    function l1AppSender() external view returns (address) { return _l1AppSender; }
    // Not used in tests

    function sendMessageToL1(address _destination, bytes calldata _data, uint256 _gasLimit) external returns (uint256) {
        // Gate: envelope must encode fromApp == msg.sender
        (, bytes memory envelope, ) = abi.decode(_data[4:], (address, bytes, uint256));
        (address from, ) = abi.decode(envelope, (address, bytes));
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        // Enqueue message to be applied later from L1 side.
        bytes32 id = keccak256(abi.encodePacked(address(this), ++l2ToL1Nonce, _destination, _data, _gasLimit, msg.sender));
        l2ToL1Ids.push(id);
        l2ToL1Messages[id] = L2ToL1Message({
            id: id,
            to: _destination,
            data: _data,
            gasLimit: _gasLimit,
            // Preserve caller identity as L2 sender (tests may mirror with connector as msg.sender)
            l2SenderSaved: address(this),
            pending: true
        });
        emit MessageSentToL1FromBridge(_destination, _data, _gasLimit);
        return 0;
    }

    function l2Sender() external view returns (address) {
        return _l2Sender;
    }
    function l2AppSender() external view returns (address) { return _l2AppSender; }
    // Not used in tests

    function sendMessageToL2(address _destination, bytes calldata _data, uint256 _gasLimit) external {
        // Gate: envelope must encode fromApp == msg.sender
        (, bytes memory envelope, ) = abi.decode(_data[4:], (address, bytes, uint256));
        (address from, ) = abi.decode(envelope, (address, bytes));
        require(from == msg.sender, InvalidCaller("not app sender", from, msg.sender));
        if (queueL1ToL2) {
            // Enqueue message to be applied later from L2 side.
            bytes32 id = keccak256(abi.encodePacked(address(this), ++l1ToL2Nonce, _destination, _data, _gasLimit, msg.sender));
            l1ToL2Ids.push(id);
            l1ToL2Messages[id] = L1ToL2Message({
                id: id,
                to: _destination,
                data: _data,
                gasLimit: _gasLimit,
                l1SenderSaved: msg.sender,
                pending: true
            });
            emit MessageQueuedToL2(_destination, _data, _gasLimit, id);
            return;
        }
        _l1Sender = msg.sender;
        // Simulate sending a message to L2. l1Sender() returns the sender that sent (on l1) this message
        (bool success, bytes memory revertReason) = _destination.call{gas: _gasLimit}(_data);
        if (revertOnMessageFailure) {
            require(success, ExternalCallReverted("send message to L2", _destination, revertReason));
        }
        emit MessageSentToL2FromBridge(_destination, _data, _gasLimit);
        _l1Sender = address(0);
    }

    function setL1Sender(address sender) public {
        _l1Sender = sender;
    }

    function setL2Sender(address sender) public {
        _l2Sender = sender;
    }

    function setL1AppSender(address appSender) public {
        _l1AppSender = appSender;
    }

    function setL2AppSender(address appSender) public {
        _l2AppSender = appSender;
    }

    function setRevertOnMessageFailure(bool _revertOnMessageFailure) public {
        revertOnMessageFailure = _revertOnMessageFailure;
    }

    function setQueueL1ToL2(bool _queue) public {
        queueL1ToL2 = _queue;
    }

    function applyL2ToL1Messages(bytes[] calldata bridgeMessages) external returns (uint256 applied) {
        for (uint256 i = 0; i < bridgeMessages.length; i++) {
            // For the test bridge, the message is just the id encoded as bytes32
            bytes32 id = abi.decode(bridgeMessages[i], (bytes32));
            L2ToL1Message storage message = l2ToL1Messages[id];
            if (!message.pending) {
                continue;
            }
            message.pending = false;
            address previousSender = _l2Sender;
            _l2Sender = message.l2SenderSaved;
            (bool success, bytes memory revertReason) = message.to.call{gas: message.gasLimit}(message.data);
            if (revertOnMessageFailure) {
                require(success, ExternalCallReverted("apply queued L2->L1", message.to, revertReason));
            }
            _l2Sender = previousSender;
            applied++;
        }
    }

    // Test-only helper: mirror an L2->L1 message into this L1 connector, preserving the original L2 connector identity
    function mirrorL2ToL1Message(address to, bytes calldata data, uint256 gasLimit, address l2SenderSaved) external {
        bytes32 id = keccak256(abi.encodePacked(address(this), ++l2ToL1Nonce, to, data, gasLimit, l2SenderSaved));
        l2ToL1Ids.push(id);
        l2ToL1Messages[id] = L2ToL1Message({ id: id, to: to, data: data, gasLimit: gasLimit, l2SenderSaved: l2SenderSaved, pending: true });
        emit MessageSentToL1FromBridge(to, data, gasLimit);
    }

    

    // Forward from L1 into provided `to` address; unwrap envelope to set app-sender context
    function forwardFromL1(address to, bytes calldata data, uint256 gasLimit) external {
        address prev = _l1Sender;
        _l1Sender = msg.sender;
        (address appSender, bytes memory inner) = abi.decode(data, (address, bytes));
        address prevApp = _l1AppSender;
        _l1AppSender = appSender;
        (bool success, bytes memory revertReason) = to.call{gas: gasLimit}(inner);
        require(success, ExternalCallReverted("forward L1->L2", to, revertReason));
        _l1Sender = prev;
        _l1AppSender = prevApp;
    }

    function forwardFromL2(address to, bytes calldata data, uint256 gasLimit) external {
        (gasLimit);
        // l2Sender is set by applyL2ToL1Messages prior to this call when coming from the queue.
        (address appSender, bytes memory inner) = abi.decode(data, (address, bytes));
        address prevApp = _l2AppSender;
        _l2AppSender = appSender;
        (bool success, bytes memory reason) = to.call(inner);
        require(success, ExternalCallReverted("forward L2->L1", to, reason));
        _l2AppSender = prevApp;
        emit ForwardedFromL2(to, data, gasLimit);
    }

    // helpers for tests (read the queue)
    function getL2ToL1Message(bytes32 id) external view returns (L2ToL1Message memory) {
        return l2ToL1Messages[id];
    }
    function getL2ToL1MessageIds(uint256 from, uint256 max) external view returns (bytes32[] memory ids) {
        uint256 totalIds = l2ToL1Ids.length;
        if (from >= totalIds) return new bytes32[](0);
        uint256 toIndex = from + max;
        if (toIndex > totalIds) toIndex = totalIds;
        uint256 resultLength = toIndex - from;
        ids = new bytes32[](resultLength);
        for (uint256 i = 0; i < resultLength; i++) ids[i] = l2ToL1Ids[from + i];
    }

    // helpers for tests (read the L1->L2 queue)
    function getL1ToL2Message(bytes32 id) external view returns (L1ToL2Message memory) {
        return l1ToL2Messages[id];
    }
    function getL1ToL2MessageIds(uint256 from, uint256 max) external view returns (bytes32[] memory ids) {
        uint256 totalIds = l1ToL2Ids.length;
        if (from >= totalIds) return new bytes32[](0);
        uint256 toIndex = from + max;
        if (toIndex > totalIds) toIndex = totalIds;
        uint256 resultLength = toIndex - from;
        ids = new bytes32[](resultLength);
        for (uint256 i = 0; i < resultLength; i++) ids[i] = l1ToL2Ids[from + i];
    }

    receive() external payable {}


}
