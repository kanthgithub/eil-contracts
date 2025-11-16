// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/SlashOutput.sol";

/// @notice Test double that accepts both registry and dispute callbacks on L1.
contract TestL1PaymasterReceiver {
    event TestChainInfoAdded(address l1XlpAddress, address l2XlpAddress);
    event TestStakeUnlocked(address l1XlpAddress);
    event TestSlashedReceived(SlashOutput slashPayload);

    function onL1XlpChainInfoAdded(address l1XlpAddress, address l2XlpAddress) external {
        emit TestChainInfoAdded(l1XlpAddress, l2XlpAddress);
    }

    function onL1XlpStakeUnlocked(address l1XlpAddress) external {
        emit TestStakeUnlocked(l1XlpAddress);
    }

    function onXlpSlashedMessage(SlashOutput calldata slashPayload) external {
        emit TestSlashedReceived(slashPayload);
    }
}
