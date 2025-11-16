// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct ChainInfo {
    // L2 application endpoint (paymaster/registry) that should receive forwarded calls
    address paymaster;
    // L1 connector for this chain (expected msg.sender on L1 inbound)
    address l1Connector; // IL1Bridge connector for this chain
    // L2 connector address for this chain (destination for L1->L2 send)
    address l2Connector;
    // Xlp's L2 address on this chain
    address l2XlpAddress;
}
