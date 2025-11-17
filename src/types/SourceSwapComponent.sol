// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Asset.sol";
import "./AtomicSwapFeeRule.sol";

/**
 * A struct containing all information related to the source chain of the Atomic Swap.
 */
struct SourceSwapComponent {
    uint256 chainId;
    address paymaster;
    address payable sender;
    Asset[] assets;
    AtomicSwapFeeRule feeRule;
    uint256 senderNonce;
    address[] allowedXlps;
}
