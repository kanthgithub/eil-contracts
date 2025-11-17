// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../bridges/arbitrum/IArbOutbox.sol";

contract MockArbOutbox is IArbOutbox {
    address private _l2Sender;

    event Executed(
        bytes32[] proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes data
    );

    function setL2Sender(address sender) external {
        _l2Sender = sender;
    }

    function l2ToL1Sender() external view returns (address) {
        return _l2Sender;
    }

    function executeTransaction(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external {
        emit Executed(proof, index, l2Sender, to, l2Block, l1Block, l2Timestamp, value, data);
    }
}

