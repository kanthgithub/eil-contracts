// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../../interfaces/IOriginSwapManager.sol";
import "../../types/AtomicSwapVoucher.sol";
import "../../types/AtomicSwapVoucherRequest.sol";
import "../../types/DestinationSwapComponent.sol";
import "../Errors.sol";

library AtomicSwapUtils {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes;

    /**
     * create voucher request id, by hashing the voucher request struct
     * @return requestId the voucher request id
     */
    function getVoucherRequestId(AtomicSwapVoucherRequest memory voucherRequest) internal pure returns (bytes32) {
        return keccak256(abi.encode(voucherRequest));
    }

    /**
     * verify if the voucher signature is valid
     * revert if the signature is invalid.
     */
    function verifyVoucherSignature(
        AtomicSwapVoucher memory voucher,
        DestinationSwapComponent memory destComponent
    ) internal pure {
        if (!isValidVoucherSignature(voucher, destComponent)) {
            revert SignerAddressMismatch(voucher.originationXlpAddress);
        }
    }

    /**
     * check if the voucher signature is valid
     * @return true if the signature is valid, false otherwise
     */
    function isValidVoucherSignature(
        AtomicSwapVoucher memory voucher,
        DestinationSwapComponent memory destComponent
    ) internal pure returns (bool) {
        bytes memory message = abi.encode(
            destComponent,
            voucher.requestId,
            voucher.originationXlpAddress,
            voucher.expiresAt,
            uint8(voucher.voucherType)
        );
        bytes32 messageHash = message.toEthSignedMessageHash();
        address signer = messageHash.recover(voucher.xlpSignature);
        return voucher.originationXlpAddress == signer;
    }
}
