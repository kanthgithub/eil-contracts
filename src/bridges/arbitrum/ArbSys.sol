// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// See https://docs.arbitrum.io/how-arbitrum-works/l2-to-l1-messaging
interface ArbSys {
    function sendTxToL1(address _destination, bytes calldata _data) external returns (uint256);
    function arbTxL1Sender() external view returns (address);
}

