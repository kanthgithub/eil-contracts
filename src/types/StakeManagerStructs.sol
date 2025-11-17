// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Enums.sol";
import "./LegStakeInfo.sol";
import "./InsolvencyDisputePayout.sol";

// Longest-array selection window winners (per pre/post window)
struct WindowWinners {
    uint256 bestCount;
    address payable originWinner;
    address payable destinationWinner;
    uint256 tieBreakProofTimestamp;
}

// Winners aggregation for a (xlp, chain pair, dispute type)
struct WinnersByPair {
    WindowWinners pre;
    WindowWinners post;
    bool prePresent;
    bool postPresent;
    address payable l1PullWinner;
}

// Cached origin leg metadata per requestIdsHash
struct OriginLegRecord {
    uint256 count;
    uint256 firstRequestedAt;
    uint256 lastRequestedAt;
    uint256 disputeTimestamp;
    address payable l1Beneficiary;
}

// Cached destination leg metadata per requestIdsHash
struct DestinationLegRecord {
    uint256 count;
    uint256 proofTimestamp;
    uint256 firstProveTimestamp;
    address payable l1Beneficiary;
}

// Dispute message pair metadata
struct PairMetadata {
    address l1Xlp;
    uint256 origChain;
    uint256 destChain;
    DisputeType disputeType;
}

// Single-beneficiary slashed stake pool (non-insolvency dispute types)
struct SingleSlashPool {
    uint256 amount;
    uint256 claimableAt;
    bool paidOut;
    address payable beneficiary;
    DisputeType disputeType;
}

// Claimed flags per role
struct RoleClaims {
    bool preOrigin;
    bool preDestination;
    bool postOrigin;
    bool postDestination;
    bool l1Pull;
}

struct ChainStakeState {
    uint256 stake;
    uint256 withdrawTime;
    LegStakeInfo origin;
    LegStakeInfo destination;
}

struct DisputeState {
    WinnersByPair winners;
    PairMetadata pair;
    RoleClaims claims;
    InsolvencyDisputePayout share;
}
