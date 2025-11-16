// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IL2XlpLogger {
    event MessageSentToL1(address indexed to, string functionName, bytes data, uint256 gasLimit);
}
