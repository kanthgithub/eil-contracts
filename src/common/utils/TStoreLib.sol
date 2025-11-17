// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/* solhint-disable no-inline-assembly */

struct TStoreUint256 {
    uint256 value;
}

struct TStoreBytes {
    bytes data;
}

library TStoreLib {
    function tstore(TStoreUint256 storage store, uint256 val) internal {
        assembly {
            tstore(store.slot, val)
        }
    }

    function tload(TStoreUint256 storage store) internal view returns (uint256 val) {
        assembly {
            val := tload(store.slot)
        }
    }

    function tstore(TStoreBytes storage store, bytes memory val) internal {
        assembly {
            let len := mload(val)
            let slot := store.slot
            let endslot := add(add(slot, len), 32)
            let diff := sub(val, slot)
            for {} lt(slot, endslot) {slot := add(slot, 0x20)} {
                tstore(slot, mload(add(slot, diff)))
            }
        }
    }

    function tload(TStoreBytes storage store) internal view returns (bytes memory val) {
        uint256 slot;
        uint256 len;
        assembly {
            slot := store.slot
            len := tload(slot)
        }
        val = new bytes(len);
        assembly {
            let endslot := add(add(slot, len), 32)
            let diff := sub(val, slot)
            for {} lt(slot, endslot) {slot := add(slot, 0x20)} {
                mstore(add(slot, diff), tload(slot))
            }
        }
    }
}
