// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct ChunkIterationContext {
    uint256 requiredNative;
    uint256 previousCreatedAt;
    bytes32 previousRequestId;
}
