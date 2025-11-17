// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

import "../common/Errors.sol";
import "./TokenDepositManager.sol";

contract GasAccountingManager is TokenDepositManager {
    address private immutable ENTRY_POINT;

    constructor(address entryPoint) {
        ENTRY_POINT = entryPoint;
    }

    function _preChargeXlpGas(address l2XlpAddress, uint256 preCharge) internal {
        uint256 balance = balances[NATIVE_ETH][l2XlpAddress];
        require(balance >= preCharge, InsufficientBalance(l2XlpAddress, balance, preCharge));
        balances[NATIVE_ETH][l2XlpAddress] = balance - preCharge;
    }

    function _refundExtraGas(address l2XlpAddress, uint256 maxUserOpCost, uint256 actualGasCostWithPost) internal {
        uint256 refund = maxUserOpCost - actualGasCostWithPost;
        balances[NATIVE_ETH][l2XlpAddress] += refund;
        depositToEntryPoint(actualGasCostWithPost);
    }

    function depositToEntryPoint(uint256 actualGasCostWithPost) public payable {
        IEntryPoint(ENTRY_POINT).depositTo{value : actualGasCostWithPost}(address(this));
    }

}
