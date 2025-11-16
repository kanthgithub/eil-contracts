// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./GasAccountingManager.sol";
import "../types/AtomicSwapVoucher.sol";
import "../types/AtomicSwapMetadataDestination.sol";
import "../types/Enums.sol";
import "../common/Errors.sol";

abstract contract DestinationSwapBase is GasAccountingManager {
    uint256 public immutable L1_SLASH_GAS_LIMIT;

    constructor(address entryPoint, uint256 l1SlashGasLimit)
        GasAccountingManager(entryPoint)
    {
        L1_SLASH_GAS_LIMIT = l1SlashGasLimit;
    }

    function _verifyVoucherNotExpired(
        DestinationSwapComponent memory voucherDest,
        AtomicSwapVoucher memory voucher
    ) internal view {
        require(
            voucherDest.expiresAt >= block.timestamp,
            VoucherRequestExpired(voucher.requestId, voucherDest.expiresAt, block.timestamp)
        );
        require(
            voucher.expiresAt >= block.timestamp,
            VoucherExpired(voucher.requestId, voucher.expiresAt, block.timestamp)
        );
    }
}
