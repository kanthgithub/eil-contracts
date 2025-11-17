// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IL1CrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);

    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external;
}

contract L1CrossDomainMessenger is IL1CrossDomainMessenger {

    event SentMessage(address indexed target, address indexed sender, bytes message, uint256 nonce);
    uint256 public messageNonce;

    function xDomainMessageSender() external view returns (address) {
        (this);
        return address(0);
    }
    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external {
        (_gasLimit);
        emit SentMessage(_target, msg.sender, _message, messageNonce);
        messageNonce++;
    }
}
