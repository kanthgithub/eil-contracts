// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IL2Bridge {

    function l1Sender() external view returns (address);
    function l1AppSender() external view returns (address);

    function sendMessageToL1(address _destination, bytes calldata _data, uint256 _gasLimit) external returns (uint256);

    /**
     * @notice Forward an L1->L2 message to the provided destination with the given calldata and gas limit.
     * @dev Implementations set an internal L1 sender context, forward the call, and clear context.
     */
    function forwardFromL1(address to, bytes calldata data, uint256 gasLimit) external;
}
