// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/Helpers.sol";

import "../AtomicSwapStorage.sol";
import "../interfaces/IDestinationSwapManager.sol";
import "../interfaces/IL2XlpPenalizer.sol";
import "../types/Enums.sol";
import "../common/Errors.sol";
import "../types/AtomicSwapMetadataDestination.sol";
import "../common/utils/AtomicSwapUtils.sol";

import "./DestinationSwapBase.sol";

contract DestinationSwapManager is DestinationSwapBase, IDestinationSwapManager, IL2XlpPenalizer {
    using AssetUtils for Asset;
    using AtomicSwapUtils for AtomicSwapVoucher;
    using AtomicSwapUtils for AtomicSwapVoucherRequest;

    address internal immutable _destinationDisputeModule;
    constructor(address entryPoint, address destinationModule, uint256 l1SlashGasLimit)
        DestinationSwapBase(entryPoint, l1SlashGasLimit)
    {
        _destinationDisputeModule = destinationModule;
    }

    /// @inheritdoc IDestinationSwapManager
    function getIncomingAtomicSwap(bytes32 requestId) external view returns (AtomicSwapMetadataDestination memory) {
        return incomingAtomicSwaps[requestId];
    }

    /// @inheritdoc IDestinationSwapManager
    function withdrawFromVoucher(AtomicSwapVoucherRequest memory voucherRequest, AtomicSwapVoucher memory voucher) public {
        require(
            voucherRequest.destination.sender == msg.sender,
            InvalidCaller("not sender", voucherRequest.destination.sender, msg.sender)
        );
        _verifyVoucherNotExpired(voucherRequest.destination, voucher);
        if ( !_withdrawFromVoucher(voucherRequest.destination, voucher) ) {
            revert SignerAddressMismatch(voucher.originationXlpAddress);
        }
        emit VoucherSpent(voucher.requestId, msg.sender, voucher.originationXlpAddress, voucher.expiresAt, voucher.voucherType);
    }

    function _withdrawFromVoucher(DestinationSwapComponent memory voucherDest, AtomicSwapVoucher memory voucher) internal returns (bool sigOk){
        AtomicSwapMetadataDestination storage atomicSwap = incomingAtomicSwaps[voucher.requestId];

        require(voucherDest.chainId == block.chainid, ChainIdMismatch(block.chainid, voucherDest.chainId));
        require(voucherDest.paymaster == address(this), AddressMismatch(address(this), voucherDest.paymaster));

        if (atomicSwap.status == AtomicSwapStatus.NONE) {
            _withdrawFromUnusedVoucher(voucherDest, voucher.originationXlpAddress, atomicSwap);
        } else {
            revert InvalidAtomicSwapStatus(voucher.requestId, AtomicSwapStatus.NONE, atomicSwap.status);
        }

        return voucher.isValidVoucherSignature(voucherDest);
    }

    function _withdrawFromUnusedVoucher(DestinationSwapComponent memory voucherDest, address from, AtomicSwapMetadataDestination storage atomicSwap) private {
        atomicSwap.status = AtomicSwapStatus.SUCCESSFUL;
        atomicSwap.paidByL2XlpAddress = from;
        for (uint256 i = 0; i < voucherDest.assets.length; i++) {
            _transferOutAssetsDecrementDeposit(voucherDest.assets[i], from, voucherDest.sender);
        }
    }

    function _getValidUntil(DestinationSwapComponent memory voucherDest, AtomicSwapVoucher memory voucher) internal pure returns (uint256)  {
        return min(voucher.expiresAt, voucherDest.expiresAt);
    }

    function destinationDisputeModule() public view returns (address) {
        return _destinationDisputeModule;
    }

    function getDestinationInsolvencyReportNonce(address reporter) external view returns (uint256) {
        return destinationInsolvencyReportNonces[reporter];
    }

    /// @inheritdoc IL2XlpPenalizer
    function accuseFalseVoucherOverride(
        AtomicSwapVoucherRequest[] calldata voucherRequests,
        AtomicSwapVoucher[] calldata voucherOverrides,
        address payable l1Beneficiary
    ) public virtual override {
        (voucherRequests, voucherOverrides, l1Beneficiary);
        _delegateToDestinationModule(msg.data);
    }

    /// @inheritdoc IL2XlpPenalizer
    function proveVoucherSpent(
        AtomicSwapVoucherRequest[] calldata voucherRequests,
        AtomicSwapVoucher[] calldata vouchers,
        address payable l1Beneficiary,
        address l2XlpAddressToSlash
    ) public virtual override {
        (voucherRequests, vouchers, l1Beneficiary, l2XlpAddressToSlash);
        _delegateToDestinationModule(msg.data);
    }

    /// @inheritdoc IL2XlpPenalizer
    function proveXlpInsolvent(
        AtomicSwapVoucherRequest[] calldata voucherRequests,
        AtomicSwapVoucher[] calldata vouchers,
        address payable l1Beneficiary,
        uint256 chunkIndex,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) public virtual override {
        (voucherRequests, vouchers, l1Beneficiary, chunkIndex, numberOfChunks, nonce, committedRequestIdsHash, committedVoucherCount);
        _delegateToDestinationModule(msg.data);
    }

    function _delegateToDestinationModule(bytes memory data) internal returns (bytes memory returndata) {
        address module = _destinationDisputeModule;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = module.delegatecall(data);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        return result;
    }
}
