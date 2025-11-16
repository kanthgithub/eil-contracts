// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/BasePaymaster.sol";
import "@account-abstraction/contracts/core/Helpers.sol";
import "@account-abstraction/contracts/core/UserOperationLib.sol";

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./L2XlpRegistry.sol";
import "./bridges/IL2Bridge.sol";
import "./common/Errors.sol";
import "./common/structs/DestinationVoucherRequestsData.sol";
import "./common/structs/SessionData.sol";
import "./common/utils/TStoreLib.sol";
import "./destination/DestinationSwapManager.sol";
import "./types/Asset.sol";
import "./types/AtomicSwapVoucher.sol";
import "./types/AtomicSwapVoucherRequest.sol";
import "./types/Enums.sol";

contract  CrossChainPaymaster is L2XlpRegistry, DestinationSwapManager, BasePaymaster, Proxy {
    using MessageHashUtils for bytes;
    uint256 public immutable POST_OP_GAS_COST;
    using TStoreLib for TStoreBytes;

    mapping(bytes32 => TStoreBytes) private _sessionData;

    address internal immutable originSwapModule;

    constructor(
        IEntryPoint _entryPoint,
        address _l2Connector,
        address _l1Connector,
        address _l1StakeManager,
        uint256 _postOpGasCost,
        uint256 _destinationL1SlashGasLimit,
        address _destinationDisputeModule,
        address _originSwapModule,
        address _owner
    )
        DestinationSwapManager(
            address(_entryPoint),
            _destinationDisputeModule,
            _destinationL1SlashGasLimit
        )
        BasePaymaster(_entryPoint, _owner)
    {
        POST_OP_GAS_COST = _postOpGasCost;
        l2Connector = IL2Bridge(_l2Connector);
        l1Connector = _l1Connector;
        l1StakeManager = _l1StakeManager;
        originSwapModule = _originSwapModule;
    }

    // any method not implemented by this contract will be delegated to the OriginSwapManager
    // (this is "delegate-based inheritance", just because the total contract size is to big to fit a single contract)
    function _implementation() internal view override returns (address) {
        return address(originSwapModule);
    }

    /// @inheritdoc BasePaymaster
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {

        bytes calldata signedPaymasterData = UserOperationLib.getSignedPaymasterData(userOp.paymasterAndData);
        (DestinationVoucherRequestsData memory destinationVoucherRequestsData) = abi.decode(signedPaymasterData, (DestinationVoucherRequestsData));
        Asset[][] memory vouchersAssetsMinimums = destinationVoucherRequestsData.vouchersAssetsMinimums;
        bytes memory paymasterSig = UserOperationLib.getPaymasterSignature(userOp.paymasterAndData);
        require(paymasterSig.length != 0, PaymasterSignatureMissing(paymasterSig));

        (AtomicSwapVoucher[] memory vouchers, SessionData memory sessionData) = abi.decode(paymasterSig, (AtomicSwapVoucher[], SessionData));
        require(vouchersAssetsMinimums.length == vouchers.length, VouchersAndMinimumsIncompatible(vouchers.length, vouchersAssetsMinimums.length));

        uint256 minValidUntil = type(uint256).max;
        // note: we precharge from the first voucher the bigger 'destinationMaxUserOpCost' value as the user already paid for it on the origin chain
        // the remainder will be assigned to the user and can be withdrawn later
        require(maxCost <= vouchers[0].voucherRequestDest.maxUserOpCost, InsufficientMaxUserOpCost(maxCost, vouchers[0].voucherRequestDest.maxUserOpCost));
        _preChargeXlpGas(vouchers[0].originationXlpAddress, vouchers[0].voucherRequestDest.maxUserOpCost);

        context = abi.encode(vouchers[0].originationXlpAddress, vouchers[0].voucherRequestDest.maxUserOpCost);

        bool sigFailed = false;
        for (uint256 i = 0; i < vouchers.length; i++) {
            AtomicSwapVoucher memory voucher = vouchers[i];
            DestinationSwapComponent memory voucherRequestDest = voucher.voucherRequestDest;
            require(voucherRequestDest.sender == userOp.sender, AddressMismatch(voucherRequestDest.sender, userOp.sender));
            if (!_withdrawFromVoucher(voucherRequestDest, voucher)) {
                //don't break. we want full gas calculation
                context = abi.encodeWithSignature("VoucherSignatureError(uint256 index)", i);
                sigFailed = true;
            }
            // validate minimum amounts for this voucher
            _validateMinimumAmountsInVoucher(voucherRequestDest.assets, vouchersAssetsMinimums[i]);
            uint256 validUntil = _getValidUntil(voucherRequestDest, voucher);
            // validUntil == 0 means no expiry, so we must exclude it
            if (validUntil != 0) {
                minValidUntil = min(minValidUntil, validUntil);
            }
        }

        bool isEphemeralSigOk = _validateEphemeralSignature(vouchers, sessionData, destinationVoucherRequestsData.ephemeralSigner);
        if (!isEphemeralSigOk) {
            context = abi.encodeWithSignature("EphemeralSignatureInvalid(address)", destinationVoucherRequestsData.ephemeralSigner);
            sigFailed = true;
        }

        _storeSessionData(userOpHash, sessionData.data);
        return (context, _packValidationData(sigFailed, uint48(minValidUntil), 0));
    }

    function _validateMinimumAmountsInVoucher(Asset[] memory voucherAssets, Asset[] memory minAssets) internal pure {
        require(voucherAssets.length == minAssets.length, VoucherAssetsAndMinimumsIncompatible(voucherAssets.length, minAssets.length));
        for (uint256 i = 0; i < minAssets.length; i++) {
            require(
                voucherAssets[i].erc20Token == minAssets[i].erc20Token,
            AddressMismatch(minAssets[i].erc20Token, voucherAssets[i].erc20Token)
            );
            require(
                voucherAssets[i].amount >= minAssets[i].amount,
            AmountMismatch("Asset below minimum", minAssets[i].amount, voucherAssets[i].amount)
            );
        }
    }

    /**
     * @notice Validate that the ephemeral key signed the additional session data for this operation.
     * @notice The account will then be able to trust the Voucher's "sessionData" field, signed by this ephemeral key.
     * @notice This data can be used to provide a self-custodial cross-chain data passing.
     */
    function _validateEphemeralSignature(
        AtomicSwapVoucher[] memory vouchers,
        SessionData memory sessionData,
        address ephemeralSigner
    ) internal pure returns (bool sigOk){
        if (ephemeralSigner == address(0)) {
            return true;
        }
        bytes32 messageHash = getHashForEphemeralSignature(vouchers, sessionData);
        address signer = ECDSA.recover(messageHash, sessionData.ephemeralSignature);
        return ephemeralSigner == signer;
    }

    function getHashForEphemeralSignature(
        AtomicSwapVoucher[] memory vouchers,
        SessionData memory sessionData
    ) public pure returns (bytes32) {
        bytes memory messageData = abi.encode(vouchers, sessionData.data);
        return  messageData.toEthSignedMessageHash();
    }

    function _postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        (address l2XlpAddress, uint256 maxUserOpCost) = abi.decode(context, (address, uint256));
        uint256 actualGasCostWithPost = actualGasCost + POST_OP_GAS_COST * actualUserOpFeePerGas;
        _refundExtraGas(l2XlpAddress, maxUserOpCost, actualGasCostWithPost);
    }

    function getSessionData() external view returns (bytes memory) {
        bytes32 currentHash = entryPoint().getCurrentUserOpHash();
        if (currentHash == bytes32(0)) {
            revert SessionDataNotFound(currentHash);
        }
        return _loadSessionData(currentHash);
    }

    function _storeSessionData(bytes32 userOpHash, bytes memory sessionData) internal {
        _sessionData[userOpHash].tstore(sessionData);
    }

    function _loadSessionData(bytes32 userOpHash) internal view returns (bytes memory) {
        bytes memory sessionData = _sessionData[userOpHash].tload();
        if (sessionData.length == 0) {
            revert SessionDataNotFound(userOpHash);
        }
        return sessionData;
    }
}
