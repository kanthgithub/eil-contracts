// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/Enums.sol";
import "../types/AtomicSwapMetadataDestination.sol";
import "../types/AtomicSwapVoucher.sol";
import "../types/AtomicSwapVoucherRequest.sol";
/**
 * @title IDestinationSwapManager
 * @notice Interface defining the core functionality for managing atomic swaps between chains.
 * @notice Handles the creation, signing, execution and cancellation of cross-chain atomic swaps.
 */
interface IDestinationSwapManager {

    event VoucherSpent(bytes32 indexed requestId, address indexed sender, address payable indexed originationXlpAddress, uint256 expiresAt, VoucherType voucherType);

    /**
     * @notice View function to get the full details of a an existing atomic swap.
     * @param id - identifier of the atomic swap.
     * @return atomicSwap - full details of the atomic swap.
     */
    function getIncomingAtomicSwap(bytes32 id) external view returns (AtomicSwapMetadataDestination memory atomicSwap);

    /**
     * @notice Called by the user on the destination chain to retrieve xlp funds and finalize the swap.
     * @param voucherRequest - details of the voucher request from the origin chain.
     * @param voucher - details of the current voucher.
     */
    function withdrawFromVoucher(AtomicSwapVoucherRequest memory voucherRequest, AtomicSwapVoucher memory voucher) external;
}
