// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract NoopTarget {
    // Accept any calldata, do nothing, do not revert.
    fallback() external payable {}
    receive() external payable {}
}

