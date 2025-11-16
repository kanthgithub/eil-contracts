// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@account-abstraction/contracts/core/BaseAccount.sol";

contract DummyAccount is BaseAccount {

    receive() external payable {}

    /// @inheritdoc BaseAccount
    function entryPoint() public pure  override returns (IEntryPoint) {
        return IEntryPoint(address(0));
    }

    /// @inheritdoc BaseAccount
    function _validateSignature(
        PackedUserOperation calldata,
        bytes32
    ) internal view virtual override returns (uint256) {
        return 0; // Dummy implementation
    }

    function _requireFromEntryPoint() internal view override virtual {
        (msg.sender);
    }

        // Require the function call went through EntryPoint or owner
    function _requireForExecute() internal view override virtual {
        //don't require anything to execute
        (msg.sender);
    }
}
