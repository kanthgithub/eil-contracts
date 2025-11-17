// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract DummyTarget {
    event Received(bytes data);

    function receiveData(bytes calldata data) external {
        emit Received(data);
    }
}

