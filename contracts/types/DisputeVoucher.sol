// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Enums.sol";
import "./AtomicSwapVoucherRequest.sol";

struct DisputeVoucher {
    AtomicSwapVoucherRequest voucherRequest;
    BondType bondType; // ERC20_PERCENT or NATIVE
}
