// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/XlpEntry.sol";

/**
 * @title Layer 2 Xlp Registry Interface.
 * @notice Interface for managing xlp registrations and status across Layer 1 and Layer 2 chains.
 * @notice This interface handles xlp registration and state changes triggered by L1 Stake Manager events.
 * @notice It also provides functionality to query registered xlps.
 */
interface IL2XlpRegistry {

    /**
    * @notice Called by L1 Stake Manager via the L1 connector to indicate this chain's paymaster/connectors are activated.
    * @notice Only staked xlps can trigger this event.
    * @param l1XlpAddress - The xlp address that staked on the L1.
    * @param l2XlpAddress - The xlp address on the L2.
    */
    function onL1XlpChainInfoAdded(address l1XlpAddress, address l2XlpAddress) external;

    /**
     * @notice Called by L1 Stake Manager via the L1 connector when a xlp's stake is unlocked on L1.
     * @notice This removes the xlp from the L2 registry.
     * @param l1XlpAddress - The address of the xlp whose stake was unlocked on L1.
     */
    function onL1XlpStakeUnlocked(address l1XlpAddress) external;

    /**
     * @notice Checks if a Layer 1 xlp address is registered.
     * @param l1XlpAddress The address of the xlp on Layer 1.
     * @return bool True if the xlp is registered, false otherwise.
     */
    function isL1XlpRegistered(address l1XlpAddress) external view returns (bool);

    /**
     * @notice Checks if a Layer 2 xlp address is registered.
     * @param l2XlpAddress The address of the xlp on Layer 2.
     * @return bool True if the xlp is registered, false otherwise.
     */
    function isL2XlpRegistered(address l2XlpAddress) external view returns (bool);

    /**
     * @notice Retrieves xlp information by their L1 address.
     * @param l1XlpAddress The address of the xlp on L1.
     * @return xlp The XlpEntry containing L1 and L2 addresses for the requested xlp.
     */
    function getXlpByL1Address(address l1XlpAddress) external view returns (XlpEntry memory xlp);

    /**
     * @notice Retrieves xlp information by their L2 address.
     * @param l2XlpAddress The address of the xlp on L2.
     * @return xlp The XlpEntry containing L1 and L2 addresses for the requested xlp.
     */
    function getXlpByL2Address(address l2XlpAddress) external view returns (XlpEntry memory xlp);

    /**
     * @notice Retrieves a paginated list of registered xlps.
     * @param offset The starting position in the list of xlps.
     * @param length The maximum number of xlps to return.
     * @return xlps An array of XlpEntry containing L1 xlp addresses and their corresponding L2 xlp IDs.
     */
    function getXlps(uint256 offset, uint256 length) external view returns (XlpEntry[] memory xlps);

}
