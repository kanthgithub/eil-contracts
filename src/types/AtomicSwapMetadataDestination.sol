// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Enums.sol";

struct AtomicSwapMetadataDestination {
    AtomicSwapStatus status;
    address paidByL2XlpAddress;
}
