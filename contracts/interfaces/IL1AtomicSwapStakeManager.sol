// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../types/StakeInfo.sol";
import "../types/ChainInfo.sol";
import "../types/ChainInfoReturnStruct.sol";
import "../types/PaymasterInfo.sol";
import "../types/ReportLegs.sol";
import "../types/Enums.sol";
import "../bridges/IL1Bridge.sol";

interface IL1AtomicSwapStakeManager {

    /// @notice Emitted when a xlp's stake is locked.
    /// @param xlp The address of the xlp who locked stake.
    /// @param chainIds The chain ids supported by the xlp who locked stake.
    /// @param stake The amount of stake locked.
    event StakeLocked(
        address indexed xlp,
        uint256[] chainIds,
        uint256 stake
    );

    /// @notice Emitted once a stake is scheduled for withdrawal.
    /// @param account The xlp's account address.
    /// @param chainIds The chain ids unlocked by the xlp
    /// @param withdrawTime The timestamp when withdrawal will be available.
    event StakeUnlocked(address indexed account, uint256[] chainIds, uint256 withdrawTime);

    /// @notice Emitted when stake is successfully withdrawn.
    /// @param account The xlp's account address.
    /// @param chainIds The chain ids withdrawn by the xlp.
    /// @param withdrawAddress The address that received the withdrawn funds.
    /// @param amount The amount withdrawn.
    event StakeWithdrawn(
        address indexed account,
        uint256[] chainIds,
        address withdrawAddress,
        uint256 amount
    );

    /// @notice Emitted when a xlp's stake is slashed and a slash pool is scheduled for claims by winners.
    event StakeSlashScheduled(
        address indexed l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        DisputeType disputeType,
        bytes32 requestIdsHash,
        uint256 amount,
        uint256 claimableAt
    );

    /// @notice Emitted when chain information is added for a xlp.
    /// @param l1Xlp The L1 address of the xlp.
    /// @param l2Xlp The L2 address of the xlp.
    /// @param chainId The chain ID being added.
    /// @param paymaster The paymaster address for this chain.
    /// @param l1Connector The L1 connector address for this chain.
    /// @param l2Connector The L2 connector address for this chain.
    event ChainInfoAdded(
        address indexed l1Xlp,
        address indexed l2Xlp,
        uint256 chainId,
        address paymaster,
        address l1Connector,
        address l2Connector
    );

    /**
     * @notice Emitted when a message is sent from L2 to L1 through the canonical bridge.
     * @param to - the address on L1 that will receive the message.
     * @param data -the data payload of the message.
     * @param gasLimit - the gas limit for executing the message on L1.
     */
    event MessageSentToL2(address indexed to, string functionName, bytes data, uint256 gasLimit);

    /// @notice Emitted when a slash is recorded and becomes claimable after a delay.
    event SlashRecorded(
        address indexed l1XlpAddress,
        bytes32 indexed id,
        DisputeType disputeType,
        uint256 amount,
        address beneficiary,
        uint256 claimableAt
    );

    /// @notice Emitted when a recorded slash is claimed and funds are transferred to recipients.
    event SlashedStakeClaimed(
        address indexed l1XlpAddress,
        bytes32 indexed id,
        DisputeType disputeType,
        uint256 amount,
        address beneficiary
    );

    /// @notice Emitted when an origin dispute leg is received on L1 via the connector.
    event OriginDisputeReported(
        address indexed l1XlpAddress,
        bytes32 indexed requestIdsHash,
        uint256 originationChainId,
        uint256 destinationChainId,
        uint256 count,
        uint256 firstRequestedAt,
        uint256 lastRequestedAt,
        uint256 disputeTimestamp,
        address l1Beneficiary,
        address indexed l2XlpAddressToSlash,
        DisputeType disputeType,
        address l1Connector,
        address l2Connector,
        address paymaster
    );

    /// @notice Emitted when a destination proof leg is received on L1 via the connector.
    event DestinationProofReported(
        address indexed l1XlpAddress,
        bytes32 indexed requestIdsHash,
        uint256 originationChainId,
        uint256 destinationChainId,
        uint256 count,
        uint256 proofTimestamp,
        uint256 firstProveTimestamp,
        address l1Beneficiary,
        address indexed l2XlpAddressToSlash,
        DisputeType disputeType,
        address l1Connector,
        address l2Connector,
        address paymaster
    );

    /// @notice Adds chain information for supported chains.
    /// @param chainIds Array of chain IDs to add.
    /// @param chainsInfo Array of chain information corresponding to each chain ID.
    function addChainsInfo(uint256[] calldata chainIds, ChainInfo[] calldata chainsInfo) external payable;

    /// @notice Retrieves stake information for a xlp.
    /// @param xlp The xlp's address.
    /// @return info The stake information struct.
    function getStakeInfo(address xlp, uint256[] calldata chainIds) external view returns (StakeInfo[] memory info);

    function getChainInfos(address xlp) external view returns (ChainInfoReturnStruct[] memory info);

    /// @notice Gets all chain IDs supported by a xlp.
    /// @param xlp The xlp's address.
    /// @return Array of chain IDs.
    function getXlpChainIds(address xlp) external view returns (uint256[] memory);
    /**
     * @notice Attempt to unlock the stake.
     * @notice The value can be withdrawn (using withdrawStake) after the unstake delay.
     */
    function unlockStake(uint256[] calldata chainIds) external;

    /**
     * @notice Withdraw from the (unlocked) stake.
     * @notice Must first call unlockStake and wait for the unstakeDelay to pass.
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress, uint256[] calldata chainIds) external;

    /**
     * @notice Pull matching dispute messages from origin and destination bridges and process the slash atomically.
     * @dev Caller supplies the expected bridges, paymasters, and call data for each leg. StakeManager will
     *      invoke each bridge which will callback into this contract with the provided calldata.
     *      If the pair matches and validations pass, the xlp is slashed within the same transaction.
     */
    function pullMessagesFromBridges(
        IL1Bridge[] calldata bridges,
        bytes[][] calldata bridgeMessagesPerBridge
    ) external;

    // ============ Longest-array reporting (L2 -> L1) ============

    /// @notice Receive an origin-side dispute report leg from L2.
    /// @dev Must be called via the trusted L1 connector for the origin chain.
    function reportOriginDispute(ReportDisputeLeg calldata originLeg) external;

    /// @notice Receive a destination-side proof report leg from L2.
    /// @dev Must be called via the trusted L1 connector for the destination chain.
    function reportDestinationProof(ReportProofLeg calldata proofLeg) external;

    // ============ Longest-array claiming (L1) ============

    /// @notice Claim a share of the slashed stake based on longest-array winners for a xlp/chain-pair.
    /// @param l1XlpAddress The L1 address of the slashed xlp.
    /// @param originationChainId Origin chain id.
    /// @param destinationChainId Destination chain id.
    /// @param disputeType Dispute type for this slash.
    /// @param role Which role is claiming (see SlashShareRole enum).
    function claimSlashShare(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        DisputeType disputeType,
        SlashShareRole role
    ) external;

    /// @notice Claim a single-beneficiary slashed stake (for non-insolvency dispute types).
    /// @dev Applies to VOUCHER_OVERRIDE and UNSPENT_VOUCHER_FEE_CLAIM where no longest-array is used.
    function claimSlashSingle(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        DisputeType disputeType
    ) external;
}
