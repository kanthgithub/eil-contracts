// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasePaymaster, IEntryPoint} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {SIG_VALIDATION_SUCCESS} from "@account-abstraction/contracts/core/Helpers.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

/**
 * A simple paymaster, that accept any UserOp, up to a maximum cost.
 * Should only be used on testnets.
 * If the paymaster's balance depletes, kindly send some eth to the paymaster's address, to refill it.
 */
contract SimplePaymaster is BasePaymaster {

    uint256 public maxUserOpCost;

    error UserOpTooExpensive(uint256 cost, uint256 maxAllowedCost);

    event UserOperationSponsored(bytes32 indexed userOpHash, address indexed sender);
    event MaxUserOpCostSet(uint256 maxUserOpCost);

    constructor(IEntryPoint _entryPoint, address owner) BasePaymaster(_entryPoint, owner) {

        //set default max cost, based on current transaction's gas price
        _setMaxCost(tx.gasprice * 10_000_000);
    }

    function setMaxCost(uint256 _maxUserOpCost) public onlyOwner {
        _setMaxCost(_maxUserOpCost);
    }
    function _setMaxCost(uint256 _maxUserOpCost) internal {
        maxUserOpCost = _maxUserOpCost;
        emit MaxUserOpCostSet(_maxUserOpCost);
    }

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory, uint256) {
        require(maxCost < maxUserOpCost, UserOpTooExpensive(maxCost, maxUserOpCost));
        emit UserOperationSponsored(userOpHash, userOp.sender);
        return ("", SIG_VALIDATION_SUCCESS);
    }

    /**
     * refill paymaster balance by sending eth to it.
     */
    receive() external payable {
        entryPoint().depositTo(address(this));
    }
}
