// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Enums.sol";

/**
 xlp - xlp that was accused of wrongdoing
 requestIdsHash - hash of the requestIds of the voucherRequests
 sourceChainId - chainId of the origin chain where user has locked the deposit funds
 destinationChainId - chainId of destination chain where xlp is insolvent
 disputeType - Type of the methods on origin + destination chains called to penalize the xlp
*/
struct SlashOutput {
    address l2XlpAddressToSlash;
    bytes32 requestIdsHash;
    uint256 originationChainId;
    uint256 destinationChainId;
    DisputeType disputeType;
}
