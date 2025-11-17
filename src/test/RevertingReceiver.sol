// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Simple helper that reverts on every value transfer.
contract RevertingReceiver {
    error ForcedRevert();

    receive() external payable {
        revert ForcedRevert();
    }
}
