// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../bridges/optimism/IOptimismPortal.sol";

contract MockOptimismPortal is IOptimismPortal {
    event WithdrawalFinalized(WithdrawalTransaction wd, bytes proof);

    function finalizeWithdrawalTransaction(WithdrawalTransaction calldata _tx, bytes calldata _proof) external {
        emit WithdrawalFinalized(_tx, _proof);
    }
}

