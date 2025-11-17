// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./L1CrossDomainMessenger.sol";

interface IL2CrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);

    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external;
}

// See https://docs.optimism.io/app-developers/tutorials/bridging/cross-dom-solidity
contract L2CrossDomainMessenger is IL2CrossDomainMessenger {
    uint256 public messageNonce;
    event SentMessage(address indexed target, address indexed sender, bytes message, uint256 nonce);

    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external {
        (_gasLimit);
        emit SentMessage(_target, msg.sender, _message, messageNonce);
        messageNonce++;
    }

    function xDomainMessageSender() external pure returns (address) {
        return address(0);
    }
}
