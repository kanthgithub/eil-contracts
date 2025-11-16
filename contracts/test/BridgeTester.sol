// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../bridges/IL2Bridge.sol";
import {IL1Bridge} from "../bridges/IL1Bridge.sol";

//helper contract for testing Mock L1/L2 Bridges
contract BridgeTester {
    string public message;

    function setMessage(string calldata newMessage) external {
        message = newMessage;
    }

    function exec(address dest, bytes calldata data) external {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = dest.call(data);
        // solhint-disable-next-line gas-custom-errors
        require(success, "BridgeTester: call failed");
    }

    function viaL1Bridge(IL1Bridge bridge, address dest, bytes calldata data) external {
        bytes memory envelope = abi.encode(address(this), data);
        bytes memory forward = abi.encodeCall(IL2Bridge.forwardFromL1, (dest, envelope, 200000));
        bridge.sendMessageToL2(dest, forward, 200000);
    }

    function viaL2Bridge(IL2Bridge bridge, address dest, bytes calldata data) external {
        bytes memory envelope = abi.encode(address(this), data);
        bytes memory forward = abi.encodeCall(IL1Bridge.forwardFromL2, (dest, envelope, 200000));
        bridge.sendMessageToL1(dest, forward, 200000);
    }
}
