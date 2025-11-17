// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IOriginSwapManager.sol";
import "../common/IL2XlpLogger.sol";

interface IL2XlpPenalizer is IL2XlpLogger {

    event InsolvencyProofChunk(
        bytes32 indexed reportId,
        uint256 indexed chunkIndex,
        uint256 indexed numberOfChunks,
        uint256 chunkSize,
        uint256 chunkTimestamp
    );

    event InsolvencyProofStarted(
        bytes32 indexed reportId,
        address indexed reporter,
        address indexed l2XlpAddressToSlash,
        address l1Beneficiary,
        uint256 originationChainId,
        uint256 destinationChainId,
        uint256 numberOfChunks,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount,
        uint256 firstChunkTimestamp
    );

    event FalseVoucherOverrideAccused(
        bytes32 indexed requestId,
        address indexed accusedXlp,
        address indexed accuser,
        address paidByXlp,
        address l1Beneficiary);

    event ProvenXlpInsolvent(
        bytes32 indexed requestId,
        address indexed xlpToPenalize,
        address indexed prover,
        address l1Beneficiary
    );

    event ProvenVoucherSpent(
        bytes32 indexed requestId,
        address indexed xlpToPenalize,
        address indexed prover,
        address l1Beneficiary
    );

    /**
     * @notice Called when the xlp failed to fulfill vouchers and start user assets recovery.
     * Called by the user or an alternative xlp on the destination chain to initiate slashing process on L1 through a canonical bridge message.
     * If called by the voucher request sender, the voucher request is cancelled and cannot be fulfilled.
     * The voucher request sender will get its funds back on the origin chain.
     * If called by an alternative xlp it must lock the funds to cover and later fulfill the voucher request.
     * @param voucherRequests - details of voucher requests from the origin chain.
     * @param vouchers - details of the current vouchers.
     * @param l1Beneficiary - L1 address that will be compensated with the xlp's stake.
     */
    function proveXlpInsolvent(
        AtomicSwapVoucherRequest[] calldata voucherRequests,
        AtomicSwapVoucher[] calldata vouchers,
        address payable l1Beneficiary,
        uint256 chunkIndex,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) external;

    /**
     * @notice Called on the destination chain by anyone involved in a dispute to inform the L1 chain about the xlp that actually fulfilled the swap(s).
     * @param voucherRequests - details of the voucher requests from the origin chain.
     * @param voucherOverrides - details of the voucher overrides.
     * @param l1Beneficiary - L1 address that will be compensated with the xlp's stake.
     */
    function accuseFalseVoucherOverride(AtomicSwapVoucherRequest[] calldata voucherRequests, AtomicSwapVoucher[] calldata voucherOverrides, address payable l1Beneficiary) external;

    /**
     * @notice Called on the destination chain by anyone involved in a dispute to inform the L1 chain that the voucher(s) were spent.
     * @param voucherRequests - details of the voucher requests from the origin chain.
     * @param vouchers - details of the vouchers.
     * @param l1Beneficiary - L1 address that will be compensated with the xlp's stake.
     * @param l2XlpAddressToSlash - address of the xlp that made a fraudulent claim of the unspent voucher fee.
     */
    function proveVoucherSpent(AtomicSwapVoucherRequest[] calldata voucherRequests, AtomicSwapVoucher[] calldata vouchers, address payable l1Beneficiary, address l2XlpAddressToSlash) external;
}
