// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";

import "./bridges/IL1Bridge.sol";
import "./common/Errors.sol";
import "./common/utils/BridgeMessengerLib.sol";
import "./interfaces/IL1AtomicSwapStakeManager.sol";
import "./interfaces/IL2XlpDisputeManager.sol";
import "./interfaces/IL2XlpRegistry.sol";
import "./types/BridgeContext.sol";
import "./types/ChainInfoReturnStruct.sol";
import "./types/InsolvencyDisputePayout.sol";
import "./types/LegStakeInfo.sol";
import "./types/ReportLegs.sol";
import "./types/StakeManagerStructs.sol";
import "./types/XlpInsolvencyPool.sol";

contract L1AtomicSwapStakeManager is IL1AtomicSwapStakeManager, Ownable {
    struct Config {
        uint256 claimDelay;
        uint256 destBeforeOriginMinGap;
        uint256 minStakePerChain;
        uint256 unstakeDelay;
        uint256 maxChainsPerXlp;
        uint256 l2SlashedGasLimit;
        uint256 l2StakedGasLimit;
        address owner;
    }

    uint256 public immutable CLAIM_DELAY;
    uint256 public immutable DEST_BEFORE_ORIGIN_MIN_GAP;
    uint256 public immutable MIN_STAKE_PER_CHAIN;
    uint256 public immutable MAX_CHAINS_PER_XLP;
    uint256 public immutable UNSTAKE_DELAY;
    uint256 public immutable L2_SLASHED_GAS_LIMIT;
    uint256 public immutable L2_STAKED_GAS_LIMIT;

    address private _activePullSender;

    constructor(Config memory config) Ownable(config.owner) {
        CLAIM_DELAY = config.claimDelay;
        DEST_BEFORE_ORIGIN_MIN_GAP = config.destBeforeOriginMinGap;
        MIN_STAKE_PER_CHAIN = config.minStakePerChain;
        UNSTAKE_DELAY = config.unstakeDelay;
        MAX_CHAINS_PER_XLP = config.maxChainsPerXlp;
        L2_SLASHED_GAS_LIMIT = config.l2SlashedGasLimit;
        L2_STAKED_GAS_LIMIT = config.l2StakedGasLimit;
    }

    /// @notice maps xlps to their per-chain stake state including leg stakes
    mapping(address xlp => mapping(uint256 chainId => ChainStakeState state)) private _chainStakeStates;

    /// @notice maps chains to paymasters, that the stake manager trusts to call the paymaster.penalizeXlp on the appropriate chain, to initiate slashing
    mapping(address xlp => mapping(uint256 chainId => ChainInfo)) private chainsInfos;

    /// @notice
    mapping(address xlp => uint256[] chainIds) public xlpChainIds;

    mapping(address l2XlpAddress => address xlp) public xlpAddressReverseLookup;

    // Keyed by keccak256(abi.encode(l1Xlp, origChain, destChain, disputeType))
    mapping(bytes32 disputeId => mapping(bytes32 requestIdsHash => OriginLegRecord)) private _originLegs;
    mapping(bytes32 disputeId => mapping(bytes32 requestIdsHash => DestinationLegRecord)) private _destLegs;

    // Single-beneficiary pools keyed per (xlp, origChain, destChain)
    mapping(bytes32 poolId => SingleSlashPool) private _singleSlashPools;
    mapping(bytes32 disputeId => DisputeState) private _disputes;

    mapping(address xlp => XlpInsolvencyPool) private _xlpInsolvencyPools;
    mapping(bytes32 poolId => bool counted) private _insolvencyPairCounted;

    function _disputeId(address l1Xlp, uint256 origChain, uint256 destChain, DisputeType disputeType) internal pure returns (bytes32) {
        return keccak256(abi.encode(l1Xlp, origChain, destChain, disputeType));
    }

    function _poolId(address l1Xlp, uint256 origChain, uint256 destChain) internal pure returns (bytes32) {
        return keccak256(abi.encode(l1Xlp, origChain, destChain));
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function pullMessagesFromBridges(
        IL1Bridge[] calldata bridgesConnectors,
        bytes[][] calldata bridgeMessagesPerBridge
    ) external {
        require(bridgesConnectors.length == bridgeMessagesPerBridge.length, InvalidLength("bridges and messages length", bridgesConnectors.length, bridgeMessagesPerBridge.length));
        require(_activePullSender == address(0), InvalidCaller("pull reentrancy", address(0), msg.sender));
        _activePullSender = msg.sender;
        for (uint256 i = 0; i < bridgesConnectors.length; i++) {
            // EOA -> SM -> connector -> bridge -> SM.reportDestinationProof()/reportOriginDispute()
            bridgesConnectors[i].applyL2ToL1Messages(bridgeMessagesPerBridge[i]);
        }
        _activePullSender = address(0);
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function addChainsInfo(uint256[] calldata chainIds, ChainInfo[] calldata chainsInfo) public payable {
        require(
            chainIds.length == chainsInfo.length,
            InvalidLength("chainIds/chainsInfo", chainIds.length, chainsInfo.length)
        );
        // Require stake to match chains count
        uint256 requiredStake = chainIds.length * MIN_STAKE_PER_CHAIN;
        require(msg.value == requiredStake, AmountMismatch("stake per chains", requiredStake, msg.value));
        for (uint256 i = 0; i < chainIds.length; i++) {
            _addChainInfo(chainIds[i], chainsInfo[i]);
            _initializeChainStakeState(_chainStakeStates[msg.sender][chainIds[i]]);
        }
        require(
            xlpChainIds[msg.sender].length <= MAX_CHAINS_PER_XLP,
            ChainLimitReached(msg.sender, MAX_CHAINS_PER_XLP, xlpChainIds[msg.sender].length)
        );
        emit StakeLocked(msg.sender, chainIds, msg.value);
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function getStakeInfo(
        address xlp,
        uint256[] calldata chainIds
    ) public view returns (StakeInfo[] memory info) {
        info = new StakeInfo[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            ChainStakeState storage chainState = _chainStakeStates[xlp][chainIds[i]];
            info[i] = StakeInfo({ stake: chainState.stake, withdrawTime: chainState.withdrawTime });
        }
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function getChainInfos(address xlp) public view returns (ChainInfoReturnStruct[] memory info) {
        uint256[] storage chainIds = xlpChainIds[xlp];
        info = new ChainInfoReturnStruct[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            ChainInfo storage chainInfo = chainsInfos[xlp][chainId];
            info[i] = ChainInfoReturnStruct({
                chainId: chainId,
                paymaster: chainInfo.paymaster,
                l1Connector: chainInfo.l1Connector,
                l2Connector: chainInfo.l2Connector,
                l2XlpAddress: chainInfo.l2XlpAddress
            });
        }
        return info;
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function getXlpChainIds(address xlp) public view returns (uint256[] memory) {
        return xlpChainIds[xlp];
    }

    function _unlockStake(address xlp, uint256[] calldata chainIds) internal returns (uint256 withdrawTime) {
        uint256 len = chainIds.length;
        require(len > 0, InvalidLength("chainIds", 1, len));
        withdrawTime = block.timestamp + UNSTAKE_DELAY;
        for (uint256 i = 0; i < len; i++) {
            uint256 chainId = chainIds[i];
            ChainStakeState storage chainState = _chainStakeStates[xlp][chainId];
            require(chainState.stake >= MIN_STAKE_PER_CHAIN, NoStake(xlp));
            require(chainState.withdrawTime == 0, StakeAlreadyUnlocked(xlp, chainState.stake, chainState.withdrawTime));
            chainState.withdrawTime = withdrawTime;
            _sendStakeUnlockedEvent(xlp, chainId);
        }
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function unlockStake(uint256[] calldata chainIds) external {
        uint256 withdrawTime = _unlockStake(msg.sender, chainIds);
        emit StakeUnlocked(msg.sender, chainIds, withdrawTime);
    }

    function _withdrawStake(address xlp, uint256[] calldata chainIds) internal returns (uint256 total) {
        uint256 len = chainIds.length;
        require(len > 0, InvalidLength("chainIds", 1, len));
        for (uint256 i = 0; i < len; i++) {
            uint256 chainId = chainIds[i];
            ChainStakeState storage chainState = _chainStakeStates[xlp][chainId];
            require(chainState.stake > 0, NoStake(xlp));
            require(chainState.withdrawTime > 0, StakeNotUnlocked(xlp, chainState.stake));
            require(chainState.withdrawTime <= block.timestamp, StakeWithdrawalNotDue(xlp, chainState.withdrawTime, block.timestamp));
            total += chainState.stake;
            chainState.stake = 0;
            chainState.withdrawTime = 0;
            _resetLegInfo(xlp, chainId);
        }
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function withdrawStake(address payable withdrawAddress, uint256[] calldata chainIds) external {
        uint256 total = _withdrawStake(msg.sender, chainIds);
        emit StakeWithdrawn(msg.sender, chainIds, withdrawAddress, total);
        (bool success, bytes memory revertReason) = withdrawAddress.call{value: total}("");
        require(success, ExternalCallReverted("stake withdrawal", withdrawAddress, revertReason));
    }

    function reportOriginDispute(ReportDisputeLeg calldata originLeg) external {
        address l1XlpAddress = xlpAddressReverseLookup[originLeg.l2XlpAddressToSlash];
        ChainInfo memory originChainInfo = chainsInfos[l1XlpAddress][originLeg.originationChainId];
        _requireFromBridgeAndPaymaster(originChainInfo);
        bytes32 disputeId = _disputeId(l1XlpAddress, originLeg.originationChainId, originLeg.destinationChainId, originLeg.disputeType);
        _ensurePairMeta(disputeId, l1XlpAddress, originLeg.originationChainId, originLeg.destinationChainId, originLeg.disputeType);
        OriginLegRecord storage originLegRecord = _originLegs[disputeId][originLeg.requestIdsHash];
        _setOriginLegRecord(originLegRecord, originLeg);

        _emitOriginDisputeReported(l1XlpAddress, originLeg, _bridgeContext());

        _processPotentialMatchedPair(disputeId, originLeg.requestIdsHash);
    }

    function reportDestinationProof(ReportProofLeg calldata proofLeg) external {
        address l1XlpAddress = xlpAddressReverseLookup[proofLeg.l2XlpAddressToSlash];
        ChainInfo memory destChainInfo = chainsInfos[l1XlpAddress][proofLeg.destinationChainId];
        _requireFromBridgeAndPaymaster(destChainInfo);
        bytes32 disputeId = _disputeId(l1XlpAddress, proofLeg.originationChainId, proofLeg.destinationChainId, proofLeg.disputeType);
        _ensurePairMeta(disputeId, l1XlpAddress, proofLeg.originationChainId, proofLeg.destinationChainId, proofLeg.disputeType);
        DestinationLegRecord storage destinationLegRecord = _destLegs[disputeId][proofLeg.requestIdsHash];
        _setDestinationLegRecord(destinationLegRecord, proofLeg);

        _emitDestinationProofReported(l1XlpAddress, proofLeg, _bridgeContext());

        _processPotentialMatchedPair(disputeId, proofLeg.requestIdsHash);
    }

    function _processPotentialMatchedPair(bytes32 disputeId, bytes32 requestIdsHash) internal {
        DestinationLegRecord storage destinationLegRecord = _destLegs[disputeId][requestIdsHash];
        OriginLegRecord storage originLegRecord = _originLegs[disputeId][requestIdsHash];
        if (destinationLegRecord.count == 0 || originLegRecord.count == 0) return;
        DisputeState storage disputeState = _disputes[disputeId];
        PairMetadata storage pairMeta = disputeState.pair;
        require(pairMeta.l1Xlp != address(0), NothingToClaim("pair metadata missing", pairMeta.disputeType, disputeId));
        if (pairMeta.disputeType == DisputeType.INSOLVENT_XLP) {
            _handleInsolvencyMatch(
                disputeId,
                requestIdsHash,
                disputeState,
                pairMeta,
                originLegRecord,
                destinationLegRecord
            );
        } else {
            _handleNonInsolvencyMatch(
                pairMeta,
                destinationLegRecord,
                requestIdsHash
            );
        }
    }

    function _handleInsolvencyMatch(
        bytes32 disputeId,
        bytes32 requestIdsHash,
        DisputeState storage disputeState,
        PairMetadata storage pairMeta,
        OriginLegRecord storage originLegRecord,
        DestinationLegRecord storage destinationLegRecord
    ) internal {
        bool isPreWindow = _classifyInsolvencyWindow(originLegRecord, destinationLegRecord, disputeId, pairMeta.disputeType);

        if (_updateInsolvencyWinnersForWindow(disputeState.winners, originLegRecord, destinationLegRecord, isPreWindow)) {
            _maybeUpdatePullWinner(disputeId);
        }

        _finalizeInsolvencyMatch(disputeState, pairMeta, requestIdsHash);
    }

    function _handleNonInsolvencyMatch(
        PairMetadata storage pairMeta,
        DestinationLegRecord storage destinationLegRecord,
        bytes32 requestIdsHash
    ) internal {
        _applySingleSlash(
            pairMeta.l1Xlp,
            pairMeta.origChain,
            pairMeta.destChain,
            pairMeta.disputeType,
            requestIdsHash,
            destinationLegRecord.l1Beneficiary
        );
    }

    function _classifyInsolvencyWindow(
        OriginLegRecord storage originLegRecord,
        DestinationLegRecord storage destinationLegRecord,
        bytes32 disputeId,
        DisputeType disputeType
    ) internal view returns (bool isPreWindow) {
        require(destinationLegRecord.firstProveTimestamp > 0, NothingToClaim("destination proof missing", disputeType, disputeId));
        require(
            destinationLegRecord.proofTimestamp + DEST_BEFORE_ORIGIN_MIN_GAP <= originLegRecord.disputeTimestamp,
            ActionTooSoon(
                "destination-before-origin gap",
                destinationLegRecord.proofTimestamp,
                destinationLegRecord.proofTimestamp + DEST_BEFORE_ORIGIN_MIN_GAP,
                originLegRecord.disputeTimestamp
            )
        );

        bool isPre = originLegRecord.lastRequestedAt < destinationLegRecord.firstProveTimestamp;
        bool isPost = originLegRecord.firstRequestedAt >= destinationLegRecord.firstProveTimestamp;
        require(isPre || isPost, InvalidOrdering("mixed pre/post window"));
        return isPre;
    }

    function _updateInsolvencyWinnersForWindow(
        WinnersByPair storage winnersByPair,
        OriginLegRecord storage originLegRecord,
        DestinationLegRecord storage destinationLegRecord,
        bool isPreWindow
    ) internal returns (bool changed) {
        if (isPreWindow) {
            changed = _updateWindowWinner(winnersByPair.pre, winnersByPair.prePresent, originLegRecord, destinationLegRecord);
            winnersByPair.prePresent = true;
        } else {
            changed = _updateWindowWinner(winnersByPair.post, winnersByPair.postPresent, originLegRecord, destinationLegRecord);
            winnersByPair.postPresent = true;
        }
    }

    function _finalizeInsolvencyMatch(
        DisputeState storage disputeState,
        PairMetadata storage pairMeta,
        bytes32 requestIdsHash
    ) internal {
        _noteInsolvencyDispute(disputeState, pairMeta);
        _applyInsolvencySlash(
            pairMeta.l1Xlp,
            pairMeta.origChain,
            pairMeta.destChain,
            pairMeta.disputeType,
            requestIdsHash
        );
    }

    function claimSlashShare(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        DisputeType disputeType,
        SlashShareRole role
    ) external {
        if (disputeType == DisputeType.INSOLVENT_XLP) {
            _claimInsolvencyShare(l1XlpAddress, originationChainId, destinationChainId, role);
            return;
        }
        bytes32 disputeId = _disputeId(l1XlpAddress, originationChainId, destinationChainId, disputeType);
        bytes32 poolId = _poolId(l1XlpAddress, originationChainId, destinationChainId);
        SingleSlashPool storage pool = _singleSlashPools[poolId];
        require(pool.claimableAt != 0, NothingToClaim("pool not claimable", disputeType, disputeId));
        require(!pool.paidOut, NothingToClaim("pool already paid", disputeType, disputeId));
        require(pool.amount > 0, NothingToClaim("pool empty", disputeType, disputeId));
        require(block.timestamp >= pool.claimableAt, ActionTooSoon("claim slashed stake", 0, pool.claimableAt, block.timestamp));
        DisputeState storage disputeState = _disputes[disputeId];
        WinnersByPair storage winners = disputeState.winners;
        RoleClaims storage roleClaims = disputeState.claims;
        // Require a pre-window winner; total roles are 3 (pre only) or 5 (pre + post)
        require(winners.prePresent, NothingToClaim("pre window missing", disputeType, disputeId));
        uint256 rolesPresent = winners.postPresent ? 5 : 3;
        uint256 share = pool.amount / rolesPresent;
        _disburseSinglePoolShare(winners, roleClaims, role, share, disputeType, disputeId);
        if (_allClaimed(roleClaims, winners)) {
            pool.paidOut = true;
        }
        emit SlashedStakeClaimed(l1XlpAddress, disputeId, disputeType, share, _beneficiaryForRole(disputeState.winners, role));
    }

    function _beneficiaryForRole(WinnersByPair storage winnersByPair, SlashShareRole role) internal view returns (address payable) {
        if (role == SlashShareRole.PRE_ORIGIN) return winnersByPair.pre.originWinner;
        if (role == SlashShareRole.PRE_DESTINATION) return winnersByPair.pre.destinationWinner;
        if (role == SlashShareRole.POST_ORIGIN) return winnersByPair.post.originWinner;
        if (role == SlashShareRole.POST_DESTINATION) return winnersByPair.post.destinationWinner;
        if (role == SlashShareRole.L1_PULL) return winnersByPair.l1PullWinner;
        return payable(address(0));
    }

    function _claimInsolvencyShare(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        SlashShareRole role
    ) internal {
        (
            bytes32 disputeId,
            DisputeState storage disputeState,
            PairMetadata storage pairMeta,
            WinnersByPair storage winners,
            RoleClaims storage roleClaims,
            InsolvencyDisputePayout storage disputeShare,
            uint256 rolesPresent
        ) = _loadInsolvencyClaimState(l1XlpAddress, originationChainId, destinationChainId);

        uint256 perRolePayout = _ensureInsolvencyPerRolePayout(l1XlpAddress, pairMeta, disputeShare, rolesPresent, disputeId);

        uint256 paidAmount = _disburseInsolvencyRoleShare(winners, roleClaims, disputeShare, role, perRolePayout, disputeId);

        emit SlashedStakeClaimed(
            l1XlpAddress,
            disputeId,
            DisputeType.INSOLVENT_XLP,
            paidAmount,
            _beneficiaryForRole(disputeState.winners, role)
        );
    }

    function _allClaimed(RoleClaims storage roleClaims, WinnersByPair storage winnersState) internal view returns (bool) {
        bool preOk = !winnersState.prePresent || (roleClaims.preOrigin && roleClaims.preDestination);
        bool postOk = !winnersState.postPresent || (roleClaims.postOrigin && roleClaims.postDestination);
        return preOk && postOk && roleClaims.l1Pull;
    }

    // ===== View helpers for tests/diagnostics =====
    function getWinners(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        DisputeType disputeType
    ) external view returns (
        bool prePresent,
        address preOriginWinner,
        address preDestinationWinner,
        bool postPresent,
        address postOriginWinner,
        address postDestinationWinner,
        address l1PullWinner
    ) {
        bytes32 disputeId = _disputeId(l1XlpAddress, originationChainId, destinationChainId, disputeType);
        WinnersByPair storage winnersState = _disputes[disputeId].winners;
        return (
            winnersState.prePresent,
            winnersState.pre.originWinner,
            winnersState.pre.destinationWinner,
            winnersState.postPresent,
            winnersState.post.originWinner,
            winnersState.post.destinationWinner,
            winnersState.l1PullWinner
        );
    }

    function getPool(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId
    ) external view returns (
        bool exists,
        uint256 amount,
        uint256 claimableAt,
        bool paidOut,
        bool isSingle,
        address singleBeneficiary,
        DisputeType singleDisputeType
    ) {
        bytes32 poolId = _poolId(l1XlpAddress, originationChainId, destinationChainId);
        SingleSlashPool storage singlePool = _singleSlashPools[poolId];
        if (singlePool.claimableAt != 0) {
            return (
                true,
                singlePool.amount,
                singlePool.claimableAt,
                singlePool.paidOut,
                true,
                address(singlePool.beneficiary),
                singlePool.disputeType
            );
        }
        XlpInsolvencyPool storage xlpPool = _xlpInsolvencyPools[l1XlpAddress];
        if (xlpPool.claimableAt != 0 && _insolvencyPairCounted[poolId]) {
            return (
                true,
                0,
                xlpPool.claimableAt,
                false,
                false,
                address(0),
                DisputeType.INSOLVENT_XLP
            );
        }
        return (false, 0, 0, false, false, address(0), DisputeType.INSOLVENT_XLP);
    }

    function getLegStakeInfo(
        address l1XlpAddress,
        uint256 chainId
    ) external view returns (
        uint256 originStake,
        uint32 originPartners,
        uint256 destinationStake,
        uint32 destinationPartners
    ) {
        ChainStakeState storage chainState = _chainStakeStates[l1XlpAddress][chainId];
        LegStakeInfo storage originLeg = chainState.origin;
        LegStakeInfo storage destinationLeg = chainState.destination;
        return (
            originLeg.stake,
            originLeg.partners,
            destinationLeg.stake,
            destinationLeg.partners
        );
    }

    function getOriginLegRecord(bytes32 disputeId, bytes32 requestIdsHash) external view returns (OriginLegRecord memory) {
        OriginLegRecord memory record = _originLegs[disputeId][requestIdsHash];
        return record;
    }

    function getDestinationLegRecord(bytes32 disputeId, bytes32 requestIdsHash) external view returns (DestinationLegRecord memory) {
        DestinationLegRecord memory record = _destLegs[disputeId][requestIdsHash];
        return record;
    }

    function getPairMeta(bytes32 disputeId) external view returns (PairMetadata memory) {
        PairMetadata memory meta = _disputes[disputeId].pair;
        return meta;
    }

    function getRoleClaims(bytes32 disputeId) external view returns (RoleClaims memory) {
        RoleClaims memory claims = _disputes[disputeId].claims;
        return claims;
    }

    function getXlpInsolvencyPool(address xlp) external view returns (XlpInsolvencyPool memory) {
        XlpInsolvencyPool memory pool = _xlpInsolvencyPools[xlp];
        return pool;
    }

    function getInsolvencyDisputePayout(bytes32 disputeId) external view returns (InsolvencyDisputePayout memory) {
        InsolvencyDisputePayout memory payout = _disputes[disputeId].share;
        return payout;
    }

    function getInsolvencyPairCounted(address xlp, uint256 originationChainId, uint256 destinationChainId) external view returns (bool) {
        return _insolvencyPairCounted[_poolId(xlp, originationChainId, destinationChainId)];
    }

    function _pay(address payable to, uint256 amount) internal {
        (bool success, bytes memory revertReason) = to.call{value: amount}("");
        require(success, ExternalCallReverted("reward withdrawal", to, revertReason));
    }

    function _distributionAmount(uint256 stakeAmount) internal pure returns (uint256) {
        return (stakeAmount * 9) / 10;
    }

    function _bridgeContext() internal view returns (BridgeContext memory ctx) {
        ctx.l1Connector = msg.sender;
        IL1Bridge bridge = IL1Bridge(ctx.l1Connector);
        ctx.l2Connector = bridge.l2Sender();
        ctx.paymaster = bridge.l2AppSender();
    }

    function _initializeChainStakeState(ChainStakeState storage chainState) internal {
        chainState.stake = MIN_STAKE_PER_CHAIN;
        chainState.withdrawTime = 0;
        uint256 originPortion = MIN_STAKE_PER_CHAIN / 2;
        uint256 destinationPortion = MIN_STAKE_PER_CHAIN - originPortion;
        _setLeg(chainState.origin, originPortion);
        _setLeg(chainState.destination, destinationPortion);
    }

    function _setLeg(LegStakeInfo storage leg, uint256 stakeAmount) internal {
        leg.stake = stakeAmount;
        leg.partners = 0;
        leg.slashed = false;
    }

    function _drainChainStake(ChainStakeState storage chainState) internal {
        chainState.stake = 0;
        chainState.withdrawTime = type(uint256).max;
    }

    function _initializeSingleSlashPool(
        SingleSlashPool storage pool,
        uint256 amount,
        address payable beneficiary,
        DisputeType disputeType,
        uint256 claimableAt
    ) internal {
        pool.amount = amount;
        pool.claimableAt = claimableAt;
        pool.paidOut = false;
        pool.beneficiary = beneficiary;
        pool.disputeType = disputeType;
    }

    function _setOriginLegRecord(OriginLegRecord storage record, ReportDisputeLeg calldata leg) internal {
        record.count = leg.count;
        record.firstRequestedAt = leg.firstRequestedAt;
        record.lastRequestedAt = leg.lastRequestedAt;
        record.disputeTimestamp = leg.disputeTimestamp;
        record.l1Beneficiary = leg.l1Beneficiary;
    }

    function _setDestinationLegRecord(DestinationLegRecord storage record, ReportProofLeg calldata leg) internal {
        record.count = leg.count;
        record.proofTimestamp = leg.proofTimestamp;
        record.firstProveTimestamp = leg.firstProveTimestamp;
        record.l1Beneficiary = leg.l1Beneficiary;
    }

    function _emitOriginDisputeReported(
        address l1XlpAddress,
        ReportDisputeLeg calldata originLeg,
        BridgeContext memory context
    ) internal {
        emit OriginDisputeReported(
            l1XlpAddress,
            originLeg.requestIdsHash,
            originLeg.originationChainId,
            originLeg.destinationChainId,
            originLeg.count,
            originLeg.firstRequestedAt,
            originLeg.lastRequestedAt,
            originLeg.disputeTimestamp,
            originLeg.l1Beneficiary,
            originLeg.l2XlpAddressToSlash,
            originLeg.disputeType,
            context.l1Connector,
            context.l2Connector,
            context.paymaster
        );
    }

    function _emitDestinationProofReported(
        address l1XlpAddress,
        ReportProofLeg calldata proofLeg,
        BridgeContext memory context
    ) internal {
        emit DestinationProofReported(
            l1XlpAddress,
            proofLeg.requestIdsHash,
            proofLeg.originationChainId,
            proofLeg.destinationChainId,
            proofLeg.count,
            proofLeg.proofTimestamp,
            proofLeg.firstProveTimestamp,
            proofLeg.l1Beneficiary,
            proofLeg.l2XlpAddressToSlash,
            proofLeg.disputeType,
            context.l1Connector,
            context.l2Connector,
            context.paymaster
        );
    }

    function _loadInsolvencyClaimState(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId
    )
        internal
        view
        returns (
            bytes32 disputeId,
            DisputeState storage disputeState,
            PairMetadata storage pairMeta,
            WinnersByPair storage winners,
            RoleClaims storage roleClaims,
            InsolvencyDisputePayout storage disputeShare,
            uint256 rolesPresent
        )
    {
        disputeId = _disputeId(l1XlpAddress, originationChainId, destinationChainId, DisputeType.INSOLVENT_XLP);
        disputeState = _disputes[disputeId];
        pairMeta = disputeState.pair;
        require(pairMeta.l1Xlp != address(0), NothingToClaim("pair metadata missing", pairMeta.disputeType, disputeId));

        XlpInsolvencyPool storage xlpPool = _xlpInsolvencyPools[l1XlpAddress];
        require(xlpPool.claimableAt != 0, NothingToClaim("insolvency pool not claimable", DisputeType.INSOLVENT_XLP, disputeId));
        require(block.timestamp >= xlpPool.claimableAt, ActionTooSoon("claim slashed stake", 0, xlpPool.claimableAt, block.timestamp));

        disputeShare = disputeState.share;
        require(disputeShare.partnersCounted, NothingToClaim("insolvency share incomplete", DisputeType.INSOLVENT_XLP, disputeId));

        winners = disputeState.winners;
        require(winners.prePresent, NothingToClaim("pre window missing", DisputeType.INSOLVENT_XLP, disputeId));

        roleClaims = disputeState.claims;
        rolesPresent = winners.postPresent ? 5 : 3;
    }

    function _ensureInsolvencyPerRolePayout(
        address l1XlpAddress,
        PairMetadata storage pairMeta,
        InsolvencyDisputePayout storage disputeShare,
        uint256 rolesPresent,
        bytes32 disputeId
    ) internal returns (uint256) {
        if (!disputeShare.payoutAlreadyComputed) {
            uint256 originShare = 0;
            LegStakeInfo storage originLeg = _chainStakeStates[l1XlpAddress][pairMeta.origChain].origin;
            if (originLeg.partners > 0) {
                originShare = _distributionAmount(originLeg.stake) / originLeg.partners;
            }

            uint256 destinationShare = 0;
            LegStakeInfo storage destinationLeg = _chainStakeStates[l1XlpAddress][pairMeta.destChain].destination;
            if (destinationLeg.partners > 0) {
                destinationShare = _distributionAmount(destinationLeg.stake) / destinationLeg.partners;
            }

            uint256 totalShare = originShare + destinationShare;
            require(totalShare > 0, NothingToClaim("no insolvency stake share", DisputeType.INSOLVENT_XLP, disputeId));

            uint256 perRolePayout = rolesPresent > 0 ? totalShare / rolesPresent : 0;
            disputeShare.perRolePayout = perRolePayout;
            disputeShare.leftoverWei = totalShare - perRolePayout * rolesPresent;
            disputeShare.payoutAlreadyComputed = true;
        }

        return disputeShare.perRolePayout;
    }

    function _disburseInsolvencyRoleShare(
        WinnersByPair storage winners,
        RoleClaims storage roleClaims,
        InsolvencyDisputePayout storage disputeShare,
        SlashShareRole role,
        uint256 shareAmount,
        bytes32 disputeId
    ) internal returns (uint256) {
        if (role == SlashShareRole.PRE_ORIGIN) {
            require(!roleClaims.preOrigin, NothingToClaim("pre origin already claimed", DisputeType.INSOLVENT_XLP, disputeId));
            roleClaims.preOrigin = true;
            _pay(winners.pre.originWinner, shareAmount);
            return shareAmount;
        }

        if (role == SlashShareRole.PRE_DESTINATION) {
            require(!roleClaims.preDestination, NothingToClaim("pre destination already claimed", DisputeType.INSOLVENT_XLP, disputeId));
            roleClaims.preDestination = true;
            _pay(winners.pre.destinationWinner, shareAmount);
            return shareAmount;
        }

        if (role == SlashShareRole.POST_ORIGIN) {
            require(winners.postPresent && !roleClaims.postOrigin, NothingToClaim("post origin already claimed", DisputeType.INSOLVENT_XLP, disputeId));
            roleClaims.postOrigin = true;
            _pay(winners.post.originWinner, shareAmount);
            return shareAmount;
        }

        if (role == SlashShareRole.POST_DESTINATION) {
            require(winners.postPresent && !roleClaims.postDestination, NothingToClaim("post destination already claimed", DisputeType.INSOLVENT_XLP, disputeId));
            roleClaims.postDestination = true;
            _pay(winners.post.destinationWinner, shareAmount);
            return shareAmount;
        }

        if (role == SlashShareRole.L1_PULL) {
            require(!roleClaims.l1Pull, NothingToClaim("l1 pull already claimed", DisputeType.INSOLVENT_XLP, disputeId));
            roleClaims.l1Pull = true;
            uint256 payout = shareAmount + disputeShare.leftoverWei;
            disputeShare.leftoverWei = 0;
            _pay(winners.l1PullWinner, payout);
            return payout;
        }

        revert InvalidSlashShareRole(SlashShareRole.L1_PULL, uint8(role));
    }

    function _disburseSinglePoolShare(
        WinnersByPair storage winners,
        RoleClaims storage roleClaims,
        SlashShareRole role,
        uint256 shareAmount,
        DisputeType disputeType,
        bytes32 disputeId
    ) internal {
        if (role == SlashShareRole.PRE_ORIGIN) {
            require(winners.prePresent && !roleClaims.preOrigin, NothingToClaim("pre origin already claimed", disputeType, disputeId));
            roleClaims.preOrigin = true;
            _pay(winners.pre.originWinner, shareAmount);
            return;
        }

        if (role == SlashShareRole.PRE_DESTINATION) {
            require(winners.prePresent && !roleClaims.preDestination, NothingToClaim("pre destination already claimed", disputeType, disputeId));
            roleClaims.preDestination = true;
            _pay(winners.pre.destinationWinner, shareAmount);
            return;
        }

        if (role == SlashShareRole.POST_ORIGIN) {
            require(winners.postPresent && !roleClaims.postOrigin, NothingToClaim("post origin already claimed", disputeType, disputeId));
            roleClaims.postOrigin = true;
            _pay(winners.post.originWinner, shareAmount);
            return;
        }

        if (role == SlashShareRole.POST_DESTINATION) {
            require(winners.postPresent && !roleClaims.postDestination, NothingToClaim("post destination already claimed", disputeType, disputeId));
            roleClaims.postDestination = true;
            _pay(winners.post.destinationWinner, shareAmount);
            return;
        }

        if (role == SlashShareRole.L1_PULL) {
            require(!roleClaims.l1Pull, NothingToClaim("l1 pull already claimed", disputeType, disputeId));
            roleClaims.l1Pull = true;
            _pay(winners.l1PullWinner, shareAmount);
            return;
        }

        revert InvalidSlashShareRole(SlashShareRole.L1_PULL, uint8(role));
    }

    /// @inheritdoc IL1AtomicSwapStakeManager
    function claimSlashSingle(
        address l1XlpAddress,
        uint256 originationChainId,
        uint256 destinationChainId,
        DisputeType disputeType
    ) external {
        require(disputeType != DisputeType.INSOLVENT_XLP, InvalidDisputeType("not single payout type", DisputeType.INSOLVENT_XLP, disputeType));
        bytes32 disputeId = _disputeId(l1XlpAddress, originationChainId, destinationChainId, disputeType);
        bytes32 poolId = _poolId(l1XlpAddress, originationChainId, destinationChainId);
        SingleSlashPool storage pool = _singleSlashPools[poolId];
        require(pool.amount > 0, NothingToClaim("pool empty", disputeType, disputeId));
        require(pool.claimableAt != 0, NothingToClaim("pool not claimable", disputeType, disputeId));
        require(!pool.paidOut, NothingToClaim("pool already paid", disputeType, disputeId));
        require(pool.beneficiary != address(0), NothingToClaim("pool missing beneficiary", disputeType, disputeId));
        // Enforce claiming with the same non-insolvency dispute type that created the single pool
        require(disputeType == pool.disputeType, InvalidDisputeType("wrong dispute type for single pool", pool.disputeType, disputeType));
        require(block.timestamp >= pool.claimableAt, ActionTooSoon("claim slashed stake", 0, pool.claimableAt, block.timestamp));
        address payable beneficiary = pool.beneficiary;
        uint256 amount = pool.amount;
        pool.paidOut = true;
        _pay(beneficiary, amount);
        emit SlashedStakeClaimed(l1XlpAddress, disputeId, pool.disputeType, amount, beneficiary);
    }

    // Slash precedence helpers
    function _applyInsolvencySlash(
        address l1Xlp,
        uint256 origChain,
        uint256 destChain,
        DisputeType disputeType,
        bytes32 requestIdsHash
    ) internal {
        if (_retargetToInsolvencyPool(l1Xlp, origChain, destChain, disputeType, requestIdsHash)) {
            return;
        }
        if (disputeType == DisputeType.INSOLVENT_XLP) {
            SingleSlashPool storage singlePool = _singleSlashPools[_poolId(l1Xlp, origChain, destChain)];
            if (singlePool.claimableAt != 0 && !singlePool.paidOut && block.timestamp < singlePool.claimableAt) {
                singlePool.amount = 0;
            }
            _slashXlpIfNeeded(l1Xlp, origChain, destChain, disputeType, requestIdsHash);
        }
        SlashOutput memory slashPayload = SlashOutput({
            l2XlpAddressToSlash: chainsInfos[l1Xlp][origChain].l2XlpAddress,
            requestIdsHash: requestIdsHash,
            originationChainId: origChain,
            destinationChainId: destChain,
            disputeType: disputeType
        });
        _sendXlpSlashedEvent(slashPayload);
    }

    function _retargetToInsolvencyPool(
        address l1Xlp,
        uint256 origChain,
        uint256 destChain,
        DisputeType disputeType,
        bytes32 requestIdsHash
    ) internal returns (bool) {
        if (disputeType == DisputeType.INSOLVENT_XLP) {
            return false;
        }
        bytes32 pk = _poolId(l1Xlp, origChain, destChain);
        SingleSlashPool storage singlePool = _singleSlashPools[pk];
        if (singlePool.claimableAt == 0) {
            _slashOnceIfNeeded(l1Xlp, disputeType, requestIdsHash, origChain, destChain, payable(address(0)));
            return true;
        }
        XlpInsolvencyPool storage xlpPool = _xlpInsolvencyPools[l1Xlp];
        if (xlpPool.claimableAt != 0 && block.timestamp < xlpPool.claimableAt) {
            singlePool.amount = 0;
        }
        if (singlePool.beneficiary != address(0) && block.timestamp < singlePool.claimableAt && !singlePool.paidOut) {
            singlePool.beneficiary = payable(address(0));
        }
        return false;
    }

    function _applySingleSlash(
        address l1Xlp,
        uint256 origChain,
        uint256 destChain,
        DisputeType disputeType,
        bytes32 requestIdsHash,
        address payable singleBeneficiary
    ) internal {
        bytes32 pk = _poolId(l1Xlp, origChain, destChain);
        SingleSlashPool storage pool = _singleSlashPools[pk];
        if (pool.claimableAt == 0) {
            _slashOnceIfNeeded(l1Xlp, disputeType, requestIdsHash, origChain, destChain, singleBeneficiary);
            pool = _singleSlashPools[pk];
            pool.beneficiary = singleBeneficiary;
            pool.disputeType = disputeType;
            return;
        }
        // If already exists, continue to notify paymasters on matched pairs so late disputes are honored.
        // No additional slashing/rewarding occurs here.
        SlashOutput memory slashPayload = SlashOutput({
            l2XlpAddressToSlash: chainsInfos[l1Xlp][origChain].l2XlpAddress,
            requestIdsHash: requestIdsHash,
            originationChainId: origChain,
            destinationChainId: destChain,
            disputeType: disputeType
        });
        _sendXlpSlashedEvent(slashPayload);
        // If already exists as single (non-zero beneficiary), first wins; ignore subsequent payout changes
        // If insolvency already took over (beneficiary cleared), do nothing on rewards
    }


    function _requireFromBridgeAndPaymaster(ChainInfo memory chainInfo) internal view {
        require(msg.sender == chainInfo.l1Connector, InvalidCaller("not L1 connector", chainInfo.l1Connector, msg.sender));
        address l2Sender = IL1Bridge(chainInfo.l1Connector).l2Sender();
        require(l2Sender == chainInfo.l2Connector, InvalidCaller("not trusted L2 connector", chainInfo.l2Connector, l2Sender));
        address appSender = IL1Bridge(chainInfo.l1Connector).l2AppSender();
        require(appSender == chainInfo.paymaster, InvalidCaller("not trusted L2 paymaster", chainInfo.paymaster, appSender));
    }

    function _addChainInfo(uint256 chainId, ChainInfo calldata _chainInfo) internal {
        ChainInfo storage chainInfo = chainsInfos[msg.sender][chainId];
        require(
            chainInfo.paymaster == address(0) && chainInfo.l1Connector == address(0) && chainInfo.l2Connector == address(0),
            ChainAlreadyAdded(msg.sender, chainId, chainInfo.paymaster, chainInfo.l1Connector)
        );
        require(xlpAddressReverseLookup[_chainInfo.l2XlpAddress] == address(0) || xlpAddressReverseLookup[_chainInfo.l2XlpAddress] == msg.sender, AddressMismatch(address(0), msg.sender));
        xlpChainIds[msg.sender].push(chainId);
        xlpAddressReverseLookup[_chainInfo.l2XlpAddress] = msg.sender;
        chainInfo.paymaster = _chainInfo.paymaster;
        chainInfo.l1Connector = _chainInfo.l1Connector;
        chainInfo.l2Connector = _chainInfo.l2Connector;
        chainInfo.l2XlpAddress = _chainInfo.l2XlpAddress;
        emit ChainInfoAdded(msg.sender, chainInfo.l2XlpAddress, chainId, chainInfo.paymaster, chainInfo.l1Connector, chainInfo.l2Connector);
        _sendChainInfoAddedEvent(chainInfo);
    }

    function _resetLegInfo(address xlp, uint256 chainId) internal {
        ChainStakeState storage chainState = _chainStakeStates[xlp][chainId];
        delete chainState.origin;
        delete chainState.destination;
    }

    function _sendStakeUnlockedEvent(address l1XlpAddress, uint256 chainId) internal {
        ChainInfo storage chainInfo = chainsInfos[l1XlpAddress][chainId];
        bytes memory unstakedCallData = abi.encodeCall(IL2XlpRegistry.onL1XlpStakeUnlocked, (l1XlpAddress));
        bytes memory forward = BridgeMessengerLib.sendMessageToL2(
            address(this),
            IL1Bridge(chainInfo.l1Connector),
            chainInfo.l2Connector,
            chainInfo.paymaster,
            unstakedCallData,
            L2_STAKED_GAS_LIMIT
        );
        emit MessageSentToL2(chainInfo.l2Connector, "forwardFromL1(onL1XlpStakeUnlocked)", forward, L2_STAKED_GAS_LIMIT);
    }

    function _sendChainInfoAddedEvent(ChainInfo storage chainInfo) internal {
        bytes memory stakedCallData = abi.encodeCall(IL2XlpRegistry.onL1XlpChainInfoAdded, (msg.sender, chainInfo.l2XlpAddress));
        bytes memory forward = BridgeMessengerLib.sendMessageToL2(
            address(this),
            IL1Bridge(chainInfo.l1Connector),
            chainInfo.l2Connector,
            chainInfo.paymaster,
            stakedCallData,
            L2_STAKED_GAS_LIMIT
        );
        emit MessageSentToL2(chainInfo.l2Connector, "forwardFromL1(onL1XlpChainInfoAdded)", forward, L2_STAKED_GAS_LIMIT);
    }

    // Send slashed message to all chains
    function _sendXlpSlashedEvent(SlashOutput memory slashPayload) internal {
        address l1XlpAddress = xlpAddressReverseLookup[slashPayload.l2XlpAddressToSlash];
        ChainInfo memory sourceChainInfo = chainsInfos[l1XlpAddress][slashPayload.originationChainId];
        bytes memory slashedCallData = abi.encodeCall(IL2XlpDisputeManager.onXlpSlashedMessage, (slashPayload));
        bytes memory forward = BridgeMessengerLib.sendMessageToL2(
            address(this),
            IL1Bridge(sourceChainInfo.l1Connector),
            sourceChainInfo.l2Connector,
            sourceChainInfo.paymaster,
            slashedCallData,
            L2_SLASHED_GAS_LIMIT
        );
        emit MessageSentToL2(sourceChainInfo.l2Connector, "forwardFromL1(onXlpSlashedMessage)", forward, L2_SLASHED_GAS_LIMIT);
    }

    function _updateWindowWinner(
        WindowWinners storage windowWinners,
        bool present,
        OriginLegRecord storage originLegRecord,
        DestinationLegRecord storage destinationLegRecord
    ) internal returns (bool changed) {
        if (
            !present ||
        originLegRecord.count > windowWinners.bestCount ||
        (originLegRecord.count == windowWinners.bestCount &&
            // On equal count, prefer the earliest destination proof timestamp
            destinationLegRecord.proofTimestamp < windowWinners.tieBreakProofTimestamp)
        ) {
            windowWinners.bestCount = originLegRecord.count;
            windowWinners.originWinner = originLegRecord.l1Beneficiary;
            windowWinners.destinationWinner = destinationLegRecord.l1Beneficiary;
            windowWinners.tieBreakProofTimestamp = destinationLegRecord.proofTimestamp;
            return true;
        }
        return false;
    }

    function _maybeUpdatePullWinner(bytes32 disputeId) internal {
        WinnersByPair storage winnersByPair = _disputes[disputeId].winners;
        if ((winnersByPair.prePresent || winnersByPair.postPresent) && _activePullSender != address(0)) {
            winnersByPair.l1PullWinner = payable(_activePullSender);
        }
    }

    function _ensurePairMeta(bytes32 disputeId, address l1Xlp, uint256 origChain, uint256 destChain, DisputeType disputeType) internal {
        PairMetadata storage pairMeta = _disputes[disputeId].pair;
        if (pairMeta.l1Xlp == address(0)) {
            pairMeta.l1Xlp = l1Xlp;
            pairMeta.origChain = origChain;
            pairMeta.destChain = destChain;
            pairMeta.disputeType = disputeType;
        }
    }

    function _noteInsolvencyDispute(DisputeState storage disputeState, PairMetadata storage pairMeta) internal {
        InsolvencyDisputePayout storage share = disputeState.share;
        if (share.partnersCounted) {
            return;
        }
        address xlp = pairMeta.l1Xlp;
        XlpInsolvencyPool storage xlpPool = _xlpInsolvencyPools[xlp];
        if (xlpPool.claimableAt == 0 && _chainStakeStates[xlp][pairMeta.origChain].stake == 0 && _chainStakeStates[xlp][pairMeta.destChain].stake == 0) {
            share.partnersCounted = true;
            return;
        }
        if (xlpPool.claimableAt != 0 && block.timestamp >= xlpPool.claimableAt) {
            share.partnersCounted = true;
            return;
        }
        share.partnersCounted = true;
        if (_insolvencyPairCounted[_poolId(xlp, pairMeta.origChain, pairMeta.destChain)]) {
            return;
        }
        _insolvencyPairCounted[_poolId(xlp, pairMeta.origChain, pairMeta.destChain)] = true;
        LegStakeInfo storage originLeg = _chainStakeStates[xlp][pairMeta.origChain].origin;
        _incrementPartnersIfActive(originLeg);
        LegStakeInfo storage destinationLeg = _chainStakeStates[xlp][pairMeta.destChain].destination;
        _incrementPartnersIfActive(destinationLeg);
    }

    function _incrementPartnersIfActive(LegStakeInfo storage leg) internal {
        if (leg.stake > 0) {
            leg.partners += 1;
        }
    }

    function _slashXlpIfNeeded(
        address l1XlpAddress,
        uint256 origChain,
        uint256 destChain,
        DisputeType disputeType,
        bytes32 requestIdsHash
    ) internal {
        XlpInsolvencyPool storage xlpPool = _xlpInsolvencyPools[l1XlpAddress];
        uint256 originChainStakeBalance = _chainStakeStates[l1XlpAddress][origChain].stake;
        uint256 destinationChainStakeBalance = _chainStakeStates[l1XlpAddress][destChain].stake;
        if (originChainStakeBalance == 0 && destinationChainStakeBalance == 0) {
            return;
        }
        if (xlpPool.claimableAt == 0) {
            xlpPool.claimableAt = block.timestamp + CLAIM_DELAY;
        }

        bool windowActive = block.timestamp < xlpPool.claimableAt;

        uint256 amountToTransfer;
        amountToTransfer += _slashLegIfEligible(l1XlpAddress, origChain, _chainStakeStates[l1XlpAddress][origChain].origin, windowActive);
        amountToTransfer += _slashLegIfEligible(l1XlpAddress, destChain, _chainStakeStates[l1XlpAddress][destChain].destination, windowActive);

        if (amountToTransfer > 0) {
            emit StakeSlashScheduled(l1XlpAddress, origChain, destChain, disputeType, requestIdsHash, amountToTransfer, xlpPool.claimableAt);
            emit SlashRecorded(l1XlpAddress, _disputeId(l1XlpAddress, origChain, destChain, disputeType), disputeType, amountToTransfer, payable(address(0)), xlpPool.claimableAt);
        }
    }

    function _slashLegIfEligible(
        address l1XlpAddress,
        uint256 chainId,
        LegStakeInfo storage leg,
        bool windowActive
    ) internal returns (uint256 distributionAmount) {
        if (!windowActive || leg.slashed || leg.stake == 0) {
            return 0;
        }

        distributionAmount = _distributionAmount(leg.stake);
        leg.slashed = true;
        uint256 stakeToDeduct = leg.stake;
        _deductLegStake(l1XlpAddress, chainId, stakeToDeduct);
        _sendStakeUnlockedEvent(l1XlpAddress, chainId);
    }

    function _deductLegStake(address xlp, uint256 chainId, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        ChainStakeState storage chainState = _chainStakeStates[xlp][chainId];
        require(chainState.stake >= amount, NoStake(xlp));
        chainState.stake -= amount;
        chainState.withdrawTime = type(uint256).max;
    }

    function _slashOnceIfNeeded(
        address l1XlpAddress,
        DisputeType disputeType,
        bytes32 requestIdsHash,
        uint256 origChain,
        uint256 destChain,
        address payable legacyBeneficiary
    ) internal {
        bytes32 disputeId = _disputeId(l1XlpAddress, origChain, destChain, disputeType);
        bytes32 poolId = _poolId(l1XlpAddress, origChain, destChain);
        SingleSlashPool storage pool = _singleSlashPools[poolId];
        if (pool.claimableAt != 0) return;
        ChainStakeState storage originState = _chainStakeStates[l1XlpAddress][origChain];
        ChainStakeState storage destinationState = _chainStakeStates[l1XlpAddress][destChain];
        require(originState.stake > 0 || destinationState.stake > 0, NoStake(l1XlpAddress));
        uint256 amountToTransfer = _distributionAmount(originState.stake + destinationState.stake);
        _drainChainStake(originState);
        _drainChainStake(destinationState);

        uint256 claimableAt = block.timestamp + CLAIM_DELAY;
        emit StakeSlashScheduled(l1XlpAddress, origChain, destChain, disputeType, requestIdsHash, amountToTransfer, claimableAt);
        _initializeSingleSlashPool(pool, amountToTransfer, legacyBeneficiary, disputeType, claimableAt);
        emit SlashRecorded(l1XlpAddress, disputeId, disputeType, pool.amount, legacyBeneficiary, pool.claimableAt);
        // also send unlock events (as before) and L2 slashed callback for origin bookkeeping
        _sendStakeUnlockedEvent(l1XlpAddress, origChain);
        _sendStakeUnlockedEvent(l1XlpAddress, destChain);
        SlashOutput memory slashPayload = SlashOutput({
            l2XlpAddressToSlash: chainsInfos[l1XlpAddress][origChain].l2XlpAddress,
            requestIdsHash: requestIdsHash,
            originationChainId: origChain,
            destinationChainId: destChain,
            disputeType: disputeType
        });
        _sendXlpSlashedEvent(slashPayload);
    }

}
