// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../bridges/optimism/L1CrossDomainMessenger.sol";

contract MockL1CrossDomainMessenger is IL1CrossDomainMessenger {
    address private _xDomainMessageSender;
    event SentMessage(address indexed target, address indexed sender, bytes message, uint32 gasLimit);

    function setXDomainMessageSender(address sender) external {
        _xDomainMessageSender = sender;
    }

    function xDomainMessageSender() external view returns (address) {
        return _xDomainMessageSender;
    }

    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external {
        emit SentMessage(_target, msg.sender, _message, _gasLimit);
    }
}

