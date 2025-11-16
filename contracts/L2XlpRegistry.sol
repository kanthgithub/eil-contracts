// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "./AtomicSwapStorage.sol";
import "./interfaces/IL2XlpRegistry.sol";
import "./types/XlpEntry.sol";
import "./bridges/IL2Bridge.sol";
import "./common/Errors.sol";

abstract contract L2XlpRegistry is IL2XlpRegistry, AtomicSwapStorage {
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    /// @inheritdoc IL2XlpRegistry
    function onL1XlpChainInfoAdded(address l1XlpAddress, address l2XlpAddress) external virtual override {
        _requireFromL1StakeManager();
        registeredXlps.set(l2XlpAddress, l1XlpAddress);
        reverseLookup[l1XlpAddress] = l2XlpAddress;
    }

    /// @inheritdoc IL2XlpRegistry
    function onL1XlpStakeUnlocked(address l1XlpAddress) external {
        _requireFromL1StakeManager();
        address l2XlpAddress = reverseLookup[l1XlpAddress];
        registeredXlps.remove(l2XlpAddress);
        delete reverseLookup[l1XlpAddress];
    }

    /// @inheritdoc IL2XlpRegistry
    function getXlpByL1Address(address l1XlpAddress) external view override returns (XlpEntry memory xlp) {
        address l2XlpAddress = reverseLookup[l1XlpAddress];
        require(l2XlpAddress != address(0), XlpNotFound(l1XlpAddress));
        return XlpEntry(l1XlpAddress, l2XlpAddress);
    }

    /// @inheritdoc IL2XlpRegistry
    function isL1XlpRegistered(address l1XlpAddress) external view override returns (bool) {
        address l2XlpAddress = reverseLookup[l1XlpAddress];
        return l2XlpAddress != address(0);
    }

    /// @inheritdoc IL2XlpRegistry
    function isL2XlpRegistered(address l2XlpAddress) external view override returns (bool) {
        (bool exists,) = registeredXlps.tryGet(l2XlpAddress);
        return exists;
    }

    /// @inheritdoc IL2XlpRegistry
    function getXlpByL2Address(address l2XlpAddress) external view override returns (XlpEntry memory xlp) {
        (bool exists, address l1XlpAddress) = registeredXlps.tryGet(l2XlpAddress);
        require(exists, XlpNotFound(l2XlpAddress));
        return XlpEntry(l1XlpAddress, l2XlpAddress);
    }

    /// @inheritdoc IL2XlpRegistry
    function getXlps(uint256 offset, uint256 length) external view override returns (XlpEntry[] memory) {
        if (offset >= registeredXlps.length()) {
            return new XlpEntry[](0);
        }
        uint256 available = registeredXlps.length() - offset;
        length = available < length ? available : length;
        XlpEntry[] memory result = new XlpEntry[](length);
        for (uint256 i = 0; i < length; i++) {
            (address l2XlpAddress, address  l1XlpAddress) = registeredXlps.at(offset + i);
            result[i] = XlpEntry(l1XlpAddress, l2XlpAddress);
        }
        return result;
    }

    function _requireFromL1StakeManager() internal view virtual {
        //FOR TESTING: ignore msg.sender and l1sender if no connector.
        if (address(l2Connector) == address(0)) {
            return;
        }
        require(address(l2Connector) == msg.sender, InvalidCaller("not L2 connector", address(l2Connector), msg.sender));
        address actualSenderL1 = l2Connector.l1Sender();
        require(l1Connector == actualSenderL1, InvalidCaller("not L1 stake manager", l1Connector, actualSenderL1));
        address appSender = l2Connector.l1AppSender();
        require(l1StakeManager == appSender, InvalidCaller("not L1 stake manager", l1StakeManager, appSender));
    }

}
