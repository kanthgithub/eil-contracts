// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/Asset.sol";

interface ITokenDepositManager {

    /**
     * @notice Returns the internal token balance of a specific account.
     * @param token The address of the ERC20 token contract
     * @param account The address of the account whose balance is being queried
     * @return uint256 The current token balance of the account
     */
    function tokenBalanceOf(address token, address account) external view returns (uint256);

    /**
     * @notice Returns the internal native token balance of a specific account.
     * @param account The address of the account whose balance is being queried
     * @return uint256 The current native token balance of the account
     */
    function nativeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Deposits ERC20 tokens into this contract on behalf of a specified recipient.
     * @notice Tokens must be approved before calling this function.
     * @dev The caller must have pre-approved this contract to spend at least `amount` of tokens.
     * @param token The address of the ERC20 token contract to deposit.
     * @param to The recipient address that will own the deposited tokens within this contract.
     * @param amount The amount of tokens to deposit, in the token's smallest unit.
     */
    function tokenDepositToXlp(address token, address to, uint256 amount) external;

    /**
     * @notice Deposits multiple ERC20 tokens into this contract on behalf of a specified recipient.
     * @notice Internally calls tokenDepositToXlp for each token-amount pair.
     * @param tokens Array of ERC20 token contract addresses to deposit.
     * @param to The recipient address that will own the deposited tokens within this contract.
     * @param amounts Array of token amounts to deposit, in each token's smallest unit.
     */
    function multiTokenDepositToXlp(address[] calldata tokens, address to, uint256[] calldata amounts) external;

    /**
     * @notice Deposits native currency into this contract on behalf of a specified recipient.
     * @param to The recipient address that will own the deposited native currency within this contract.
     */
    function depositToXlp(address to) external payable;

    /**
     * @notice Withdraw tokens from the caller's internal balance to the specified external address
     * @param token The address of the ERC20 token to withdraw
     * @param to The address to send the tokens to
     * @param value The amount of tokens to withdraw
     */
    function tokenWithdraw(address token, address to, uint256 value) external;

    /**
     * @notice Withdraw native currency from the caller's internal balance to the specified xlp address
     * @param to The xlp address to send the native currency to
     * @param amount The amount of native currency to withdraw
     */
    function nativeWithdrawToXlp(address payable to, uint256 amount) external;
}
