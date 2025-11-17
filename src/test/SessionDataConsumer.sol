// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../common/structs/SessionData.sol";

interface ISessionDataProvider {
    function getSessionData() external view returns (bytes memory);
}

contract SessionDataConsumer {

    bytes public lastSessionData;

    function cacheSessionData(address paymaster) external {
        bytes memory data = ISessionDataProvider(paymaster).getSessionData();
        lastSessionData = data;
    }
}
