// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../bridges/IL1Bridge.sol";
import "../../bridges/IL2Bridge.sol";

library BridgeMessengerLib {
    function sendMessageToL1(
        address app,
        IL2Bridge l2Connector,
        address l1Connector,
        address targetOnL1,
        bytes memory payload,
        uint256 gasLimit
    ) internal returns (bytes memory forwardCalldata) {
        bytes memory envelope = abi.encode(app, payload);
        forwardCalldata = abi.encodeCall(IL1Bridge.forwardFromL2, (targetOnL1, envelope, gasLimit));
        l2Connector.sendMessageToL1(l1Connector, forwardCalldata, gasLimit);
    }

    function sendMessageToL2(
        address app,
        IL1Bridge l1Connector,
        address l2Connector,
        address targetOnL2,
        bytes memory payload,
        uint256 gasLimit
    ) internal returns (bytes memory forwardCalldata) {
        bytes memory envelope = abi.encode(app, payload);
        forwardCalldata = abi.encodeCall(IL2Bridge.forwardFromL1, (targetOnL2, envelope, gasLimit));
        l1Connector.sendMessageToL2(l2Connector, forwardCalldata, gasLimit);
    }
}
