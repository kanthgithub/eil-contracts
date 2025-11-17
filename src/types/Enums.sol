// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum AtomicSwapStatus {
    NONE,
    NEW,
    VOUCHER_ISSUED,
    CANCELLED,
    DISPUTE,
    PENALIZED,
    SUCCESSFUL,
    UNSPENT
}

enum DisputeType {
    INSOLVENT_XLP,
    VOUCHER_OVERRIDE,
    UNSPENT_VOUCHER_FEE_CLAIM
}

enum VoucherType {
    STANDARD,
    OVERRIDE,
    ALT,
    ALT_OVERRIDE
}

enum BondType {
    PERCENT,
    NATIVE
}

// Roles for sharing slashed stake in insolvency disputes
enum SlashShareRole {
    PRE_ORIGIN,
    PRE_DESTINATION,
    POST_ORIGIN,
    POST_DESTINATION,
    L1_PULL
}
