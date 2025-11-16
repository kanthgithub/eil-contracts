// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../types/SlashOutput.sol";

struct DisputeInfo {
    bool wasInitiateDisputeWithBondCalled;
    bool wasProveXlpInsolventCalled;
    // Canonical slash payload captured from the latest leg (origin/destination)
    SlashOutput slashPayload;
}
