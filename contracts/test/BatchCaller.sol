// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable avoid-low-level-calls
// solhint-disable no-inline-assembly

// Simple helper to batch two external calls to the same target in a single transaction
// Used in tests to simulate "same-block" sequences where the second call observes the
// same block.timestamp as the first call.
contract BatchCaller {
    function batch(address target, bytes calldata call1, bytes calldata call2) external payable {
        (bool firstOk, bytes memory firstRet) = target.call(call1);
        if (!firstOk) {
            assembly {
                revert(add(firstRet, 32), mload(firstRet))
            }
        }
        (bool secondOk, bytes memory secondRet) = target.call{value: msg.value}(call2);
        if (!secondOk) {
            assembly {
                revert(add(secondRet, 32), mload(secondRet))
            }
        }
    }
}
