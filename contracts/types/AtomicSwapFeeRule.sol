// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * Define the starting swap fee, the maximum swap fee, and the duration of the fee increase.
 * The actual fee paid to the liquidity provider will be determined at the time it claims the atomic swap.
 * The fee structure allows specifying up to two decimal digits of precision for fee percentage.
 * For 0.01% specify 1
 * For 0.1% specify 10
 * For 1% specify 100
 * For 10% specify 1000
 * @notice All fields denominated in the first token in assets
 */
struct AtomicSwapFeeRule {
    uint256 startFeePercentNumerator;
    uint256 maxFeePercentNumerator;
    uint256 feeIncreasePerSecond;
    uint256 unspentVoucherFee;
}
