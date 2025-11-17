// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IL1Bridge {

    function l2Sender() external view returns (address);
    function l2AppSender() external view returns (address);


    function sendMessageToL2(address _destination, bytes calldata _data, uint256 _gasLimit) external;

    /**
     * @notice Apply selected L2->L1 messages by providing bridge-specific payloads (proofs/metadata).
     * @dev Each element must be encoded per bridge requirements (e.g., Arbitrum outbox execute args, Optimism portal finalize args).
     * @param bridgeMessages Encoded messages to apply.
     * @return applied The number of messages actually applied.
     */
    function applyL2ToL1Messages(bytes[] calldata bridgeMessages) external returns (uint256 applied);

    /**
     * @notice Forward an L2->L1 message to the provided destination with the given calldata and gas limit.
     * @dev Must be invoked by the canonical L1 messenger/outbox; implementations set a transient l2Sender context.
     */
    function forwardFromL2(address to, bytes calldata data, uint256 gasLimit) external;

}
