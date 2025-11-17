// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./DestinationSwapComponent.sol";
import "./SourceSwapComponent.sol";

struct AtomicSwapVoucherRequest {
    SourceSwapComponent origination;
    DestinationSwapComponent destination;
}
