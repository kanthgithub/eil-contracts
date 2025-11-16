// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOptimismPortal {
    struct WithdrawalTransaction {
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimit;
        bytes data;
    }

    function finalizeWithdrawalTransaction(WithdrawalTransaction calldata _tx, bytes calldata _proof) external;
}

