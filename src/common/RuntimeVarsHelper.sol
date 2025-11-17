// SPDX-License-Identifier: MIT
/* solhint-disable no-inline-assembly */
pragma solidity ^0.8.28;

/**
 * A singleton helper contract that stores the runtime variables in its transient storage for all users.
 * It can be used by any Smart Account implementing the "Composable Execution" workflow.
 */
contract RuntimeVarsHelper {

    /*
     * @notice A "magic marker" to identify a "bytes32" argument in an ABI-encoded calldata as a "runtime variable key".
     */
    bytes32 constant public MAGIC_MARK = 0x00000000000000000000000011223344aabbccdd000000000000000000000000;
    bytes32 constant public MAGIC_MASK = 0xffffffffffffffffffffffffffffffffffffffff000000000000000000000000;

    // a marker for a set variable
    bytes32 constant private SET_MARK = bytes32(uint256(1));

    // thrown when getVar or replaceVars is called for a key that was not set
    error RuntimeVarNotSet(bytes32 key);

    /**
     * @notice Scans calldata for runtime variable keys and replaces them with values from transient storage.
     * @dev The returned raw bytes are without the length prefix, and should only be used in the batch building process.
     * @param data The calldata to scan and replace variables in.
     * @return Raw bytes containing the processed calldata with replaced variables.
     * @notice The variable keys are scoped per `msg.sender` address.
     * @notice The caller must be the same account that originally sets the variables to be able to query them.
     */
    function replaceVars(bytes calldata data) external view returns (bytes memory) {
        bytes memory output = data;
        for (uint256 i = 32; i <= output.length; i += 4) {
            bytes32 b = _mload(output, i);
            if (b & MAGIC_MASK == MAGIC_MARK) {
                bytes32 key = b & ~MAGIC_MASK;
                bytes32 val = getVar(key);
                _mstore(output, i, val);
            }
        }
        // return raw bytes of output, without length field
        assembly {
            return (add(output, 32), mload(output))
        }
    }

    /**
     * @notice Assigns a value to a dynamic runtime variable in the transient storage of this singleton contract.
     * @dev Variable is scoped to caller's address.
     * @param key The key to store the value under.
     * @param val The value to assign.
     */
    function setVar(bytes32 key, bytes32 val) internal {
        uint256 slot = getSlot(key);
        _tstore(slot, val);
        _tstore(slot + 1, SET_MARK);
    }

    /**
     * @notice Makes a static call to the given function and saves the result in a runtime variable.
     * @dev The function call is executed using staticcall and its result is stored as a variable.
     * @param key The variable key, scoped to the caller account.
     * @param target The address of the contract to call.
     * @param data The calldata to call the function with.
     */
    function setVarFunction(bytes32 key, address target, bytes memory data) external {
        bytes32 val;
        assembly {
            let success := staticcall(gas(), target, add(data, 0x20), mload(data), 0, 32)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            val := mload(0)
        }
        setVar(key, val);
    }

    /**
     * @notice Returns a single dynamic runtime variable value stored in the transient storage.
     * @param key The variable key, scoped to caller account.
     * @return val The value of the variable, or 0 if not set.
     */
    function getVar(bytes32 key) public view returns (bytes32 val) {
        uint256 slot = getSlot(key);
        require(_tload(slot + 1) == SET_MARK, RuntimeVarNotSet(key));
        val = _tload(slot);
    }

    /**
     * @notice Calculates a unique storage slot for a given key and caller account.
     * @dev Combines the key and msg.sender to generate a unique storage location.
     * @param key The storage key to derive the slot for.
     * @return ret The calculated storage slot ID as `bytes32`.
     */
    function getSlot(bytes32 key) internal view returns (uint256 ret) {
        assembly {
            mstore(0, key)
            mstore(32, caller())
            ret := keccak256(0, 64)
        }
    }

    function _mload(bytes memory data, uint256 offset) internal pure returns (bytes32 value) {
        assembly {
            value := mload(add(data, offset))
        }
    }

    function _mstore(bytes memory data, uint256 offset, bytes32 val) internal pure {
        assembly {
            mstore(add(data, offset), val)
        }
    }

    function _tstore(uint256 slot, bytes32 value) internal {
        assembly {tstore(slot, value)}
    }

    function _tload(uint256 slot) internal view returns (bytes32 value) {
        assembly {value := tload(slot)}
    }
}
