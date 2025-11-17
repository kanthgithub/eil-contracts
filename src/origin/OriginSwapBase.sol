// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../destination/TokenDepositManager.sol";

/**
 * @title OriginSwapBase
 * @notice Shared configuration and helpers for origin swap flows (manager + dispute module).
 */
abstract contract OriginSwapBase is TokenDepositManager {
    uint256 public immutable VOUCHER_MIN_EXPIRATION_TIME;
    uint256 public immutable DISPUTE_BOND_PERCENT;
    uint256 public immutable FLAT_NATIVE_BOND;

    uint256 public immutable TIME_TO_DISPUTE;
    uint256 public immutable USER_CANCELLATION_DELAY;
    uint256 public immutable TIME_BEFORE_DISPUTE_EXPIRES;
    uint256 public immutable L1_DISPUTE_GAS_LIMIT;

    constructor(
        uint256 voucherUnlockDelay,
        uint256 timeBeforeDisputeExpires,
        uint256 userCancellationDelay,
        uint256 voucherMinExpirationTime,
        uint256 disputeBondPercent,
        uint256 flatNativeBond,
        uint256 l1DisputeGasLimit
    ) {
        TIME_TO_DISPUTE = voucherUnlockDelay;
        TIME_BEFORE_DISPUTE_EXPIRES = timeBeforeDisputeExpires;
        USER_CANCELLATION_DELAY = userCancellationDelay;
        VOUCHER_MIN_EXPIRATION_TIME = voucherMinExpirationTime;
        DISPUTE_BOND_PERCENT = disputeBondPercent;
        FLAT_NATIVE_BOND = flatNativeBond;
        L1_DISPUTE_GAS_LIMIT = l1DisputeGasLimit;
    }

    function _getAmountWithBond(uint256 amountIn) internal view returns (uint256) {
        return amountIn * (100 + DISPUTE_BOND_PERCENT) / 100;
    }
}
