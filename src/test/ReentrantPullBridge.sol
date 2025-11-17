// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../bridges/IL1Bridge.sol";

interface IPullableStakeManager {
    function pullMessagesFromBridges(IL1Bridge[] calldata bridges, bytes[][] calldata bridgeMessagesPerBridge) external;
}

/// @dev Test helper bridge that attempts to reenter StakeManager.pullMessagesFromBridges during apply.
contract ReentrantPullBridge is IL1Bridge {
    IPullableStakeManager private immutable _stakeManager;
    bool private _attackPending;

    constructor(address stakeManager) {
        _stakeManager = IPullableStakeManager(stakeManager);
    }

    function setAttack(bool enabled) external {
        _attackPending = enabled;
    }

    function l2Sender() external pure returns (address) {
        return address(0);
    }

    function l2AppSender() external pure returns (address) {
        return address(0);
    }

    function sendMessageToL2(address, bytes calldata, uint256) external pure {
        address(0);
    }

    function forwardFromL2(address, bytes calldata, uint256) external pure {
        address(0);
    }

    function applyL2ToL1Messages(bytes[] calldata) external returns (uint256) {
        if (_attackPending) {
            _attackPending = false;
            IL1Bridge[] memory connectors = new IL1Bridge[](1);
            connectors[0] = IL1Bridge(address(this));
            bytes[][] memory messages = new bytes[][](1);
            messages[0] = new bytes[](0);
            _stakeManager.pullMessagesFromBridges(connectors, messages);
        }
        return 0;
    }
}
