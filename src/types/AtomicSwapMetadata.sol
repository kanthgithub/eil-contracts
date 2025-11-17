// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Enums.sol";

struct AtomicSwapMetadataCore {
    AtomicSwapStatus status;
    uint40 createdAt;
    uint40 voucherIssuedAt;
    uint40 voucherExpiresAt;
    VoucherType voucherType;
    address payable voucherIssuerL2XlpAddress;
}

struct AtomicSwapMetadata {
    AtomicSwapMetadataCore core;
    uint256[] amountsAfterFee;
    address payable unspentFeeXlpRecipient;
    address overrideBondToken;
    uint256 overrideBondAmount;
    address disputeBondToken;
    uint256 disputeBondAmount;
    address payable disputeBondOwner;
}
