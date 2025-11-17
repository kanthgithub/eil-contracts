// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct ChainInfoReturnStruct {
    uint256 chainId;
    address paymaster;
    address l1Connector;
    address l2Connector;
    address l2XlpAddress;
}
