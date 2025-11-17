// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../AtomicSwapStorage.sol";
import "../common/Errors.sol";
import "../types/Asset.sol";
import "../common/utils/AssetUtils.sol";
import "../interfaces/ITokenDepositManager.sol";

contract TokenDepositManager is AtomicSwapStorage, ITokenDepositManager {
    using AssetUtils for Asset;
    using SafeERC20 for IERC20;

    receive() external payable {
        balances[NATIVE_ETH][msg.sender] += msg.value;
    }

    /// @inheritdoc ITokenDepositManager
    function tokenBalanceOf(address token, address account) external view returns (uint256) {
        return balances[token][account];
    }

    /// @inheritdoc ITokenDepositManager
    function nativeBalanceOf(address account) external view returns (uint256) {
        return balances[NATIVE_ETH][account];
    }

    /// @inheritdoc ITokenDepositManager
    function depositToXlp(address to) external payable {
        balances[NATIVE_ETH][to] += msg.value;
    }

    /// @inheritdoc ITokenDepositManager
    function tokenDepositToXlp(address token, address to, uint256 amount) external {
        _tokenTransferIn(token, msg.sender, to, amount);
    }

    /// @inheritdoc ITokenDepositManager
    function multiTokenDepositToXlp(address[] memory tokens, address to, uint256[] memory amounts) external {
        require(tokens.length == amounts.length, TokensAndAmountsIncompatible(tokens.length, amounts.length));
        for (uint256 i = 0; i < amounts.length; i++) {
            _tokenTransferIn(tokens[i], msg.sender, to, amounts[i]);
        }
    }

    /// @inheritdoc ITokenDepositManager
    function nativeWithdrawToXlp(address payable to, uint256 amount) external {
        Asset memory asset = Asset({
            erc20Token: NATIVE_ETH,
            amount: amount
        });
        _transferOutAssetsDecrementDeposit(asset, msg.sender, to);
    }

    /// @inheritdoc ITokenDepositManager
    function tokenWithdraw(address erc20Token, address to, uint256 amount) external {
        Asset memory asset = Asset({
            erc20Token: erc20Token,
            amount: amount
        });
        _transferOutAssetsDecrementDeposit(asset, msg.sender, payable(to));
    }

    function _tokenTransferIn(address token, address externalFrom, address internalTo, uint256 amount) internal {
        IERC20(token).safeTransferFrom(externalFrom, address(this), amount);
        balances[token][internalTo] += amount;
    }

    function _transferOutAssetsDecrementDeposit(Asset memory asset, address from, address payable to) internal {
        address token = asset.erc20Token;
        uint256 balance = balances[token][from];
        require(balance >= asset.amount, TransferExceedsBalance(from, to, balance, asset));
        balances[token][from] = balance - asset.amount;
        asset.transfer(to);
    }

    function _tokenIncrementDeposit(Asset memory asset, address payable to) internal {
        balances[asset.erc20Token][to] += asset.amount;
    }
}



