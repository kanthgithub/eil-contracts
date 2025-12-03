# EIL (Ethereum Interoperability Layer) - Complete Architecture Analysis

## Table of Contents
1. [System Architecture Overview](#system-architecture-overview)
2. [Data Model](#data-model)
3. [Sequence Diagrams](#sequence-diagrams)
4. [Bridge Patterns](#bridge-patterns)
5. [Dispute Resolution Flows](#dispute-resolution-flows)
6. [Trust Model](#trust-model)

---

## System Architecture Overview

### High-Level Component Architecture

```mermaid
graph TB
    subgraph "User Layer"
        User[User Wallet/AA Account]
        UserOp[UserOperations Multi-Chain]
    end

    subgraph "L1 - Ethereum Mainnet"
        L1SM[L1AtomicSwapStakeManager]
        L1Stake[(XLP Stake Pool)]
        L1Disputes[(Dispute Resolution)]
        L1ArbitrumBridge[L1 Arbitrum Bridge Connector]
        L1OptimismBridge[L1 Optimism Bridge Connector]
    end

    subgraph "L2 Origin Chain - e.g., Arbitrum"
        OriginPM[CrossChainPaymaster<br/>Origin Module]
        OriginSwap[OriginSwapManager]
        OriginDispute[OriginSwapDisputeManager]
        L2OriginBridge[L2 Bridge Connector]
        OriginStorage[(Outgoing Swaps)]
    end

    subgraph "L2 Destination Chain - e.g., Optimism"
        DestPM[CrossChainPaymaster<br/>Destination Module]
        DestSwap[DestinationSwapManager]
        DestDispute[DestinationSwapDisputeManager]
        L2DestBridge[L2 Bridge Connector]
        DestStorage[(Incoming Swaps)]
    end

    subgraph "XLP (Cross-chain Liquidity Provider)"
        XLPNode[XLP Off-chain Service]
        XLPStake[Staked Capital on L1]
        XLPLiquidity[Liquidity Pools on L2s]
    end

    User -->|1. Sign Multi-Chain UserOps| UserOp
    UserOp -->|2. Lock Funds & Request Voucher| OriginPM
    OriginPM --> OriginSwap
    OriginSwap --> OriginStorage
    
    XLPNode -->|3. Monitor Requests| OriginStorage
    XLPNode -->|4. Issue Voucher| OriginSwap
    OriginSwap -->|Emit VoucherIssued Event| XLPNode
    
    User -->|5. Submit UserOp w/ Voucher| DestPM
    DestPM --> DestSwap
    DestSwap -->|6. Validate & Release Assets| DestStorage
    
    OriginSwap -.->|Dispute Messages| L2OriginBridge
    DestSwap -.->|Dispute Messages| L2DestBridge
    
    L2OriginBridge <-->|Bridge Protocol| L1ArbitrumBridge
    L2DestBridge <-->|Bridge Protocol| L1OptimismBridge
    
    L1ArbitrumBridge --> L1SM
    L1OptimismBridge --> L1SM
    
    L1SM -->|Slash Stake| L1Stake
    L1SM -->|Resolve| L1Disputes
    
    XLPNode -.->|Stake Management| L1SM
    XLPStake --> L1Stake

    style User fill:#e1f5ff
    style L1SM fill:#ffe1e1
    style OriginPM fill:#fff4e1
    style DestPM fill:#e1ffe1
    style XLPNode fill:#f0e1ff
```

### Contract Hierarchy & Delegation Pattern

```mermaid
graph TD
    subgraph "CrossChainPaymaster Contract (Main Entry Point)"
        CCP[CrossChainPaymaster]
        CCP_Proxy[Proxy Pattern]
    end

    subgraph "Inheritance Chain"
        L2XlpReg[L2XlpRegistry]
        DestSwapMgr[DestinationSwapManager]
        BasePaymaster[BasePaymaster ERC-4337]
        ProxyBase[Proxy]
    end

    subgraph "Delegated Module"
        OriginSwapMod[OriginSwapModule<br/>Separate Contract]
    end

    subgraph "Base Contracts"
        DestSwapBase[DestinationSwapBase]
        OriginSwapBase[OriginSwapBase]
        AtomicSwapStorage[AtomicSwapStorage]
        TokenDepositMgr[TokenDepositManager]
        GasAccountMgr[GasAccountingManager]
    end

    CCP ---|inherits| L2XlpReg
    CCP ---|inherits| DestSwapMgr
    CCP ---|inherits| BasePaymaster
    CCP ---|inherits| ProxyBase

    CCP -.->|delegates unimplemented| OriginSwapMod

    DestSwapMgr ---|inherits| DestSwapBase
    OriginSwapMod ---|inherits| OriginSwapBase

    DestSwapBase ---|inherits| AtomicSwapStorage
    DestSwapBase ---|inherits| TokenDepositMgr
    DestSwapBase ---|inherits| GasAccountMgr

    OriginSwapBase ---|inherits| AtomicSwapStorage

    style CCP fill:#ff9999
    style OriginSwapMod fill:#99ff99
    style DestSwapMgr fill:#9999ff
```

---

## Data Model

### Core Data Structures

```mermaid
erDiagram
    AtomicSwapVoucherRequest ||--|| SourceSwapComponent : contains
    AtomicSwapVoucherRequest ||--|| DestinationSwapComponent : contains
    
    AtomicSwapVoucher ||--|| DestinationSwapComponent : references
    AtomicSwapVoucher ||--o| bytes : "XLP Signature"
    
    SourceSwapComponent ||--|{ Asset : "origin assets"
    SourceSwapComponent ||--|| AtomicSwapFeeRule : "fee structure"
    SourceSwapComponent ||--|{ address : "allowed XLPs"
    
    DestinationSwapComponent ||--|{ Asset : "destination assets"
    
    AtomicSwapMetadata ||--|| AtomicSwapStatus : "current state"
    AtomicSwapMetadata ||--|| DisputeInfo : "dispute data"
    
    AtomicSwapMetadataDestination ||--|| AtomicSwapStatus : "dest state"
    
    ChainStakeState ||--|{ LegStakeInfo : "leg stakes"
    ChainStakeState ||--|| StakeInfo : "total stake"
    
    DisputeState ||--|| OriginLegRecord : "origin proof"
    DisputeState ||--|| DestinationLegRecord : "dest proof"
    
    AtomicSwapVoucherRequest {
        SourceSwapComponent origination
        DestinationSwapComponent destination
    }
    
    SourceSwapComponent {
        uint256 chainId
        address paymaster
        address sender
        Asset[] assets
        AtomicSwapFeeRule feeRule
        uint256 senderNonce
        address[] allowedXlps
    }
    
    DestinationSwapComponent {
        uint256 chainId
        address paymaster
        address sender
        Asset[] assets
        uint256 maxUserOpCost
        uint256 expiresAt
    }
    
    AtomicSwapVoucher {
        bytes32 requestId
        address originationXlpAddress
        DestinationSwapComponent voucherRequestDest
        uint256 expiresAt
        VoucherType voucherType
        bytes xlpSignature
    }
    
    Asset {
        address token
        uint256 amount
    }
    
    AtomicSwapMetadata {
        AtomicSwapStatus status
        uint256 lockedUntil
        uint256 bondAmount
        address bondToken
        address disputedBy
        uint256 disputeTimestamp
    }
    
    ChainStakeState {
        StakeInfo totalStake
        LegStakeInfo[] legStakes
        uint256 unstakeRequestTime
    }
```

### State Machine Diagram

```mermaid
stateDiagram-v2
    [*] --> NONE: Initial State
    
    NONE --> NEW: lockUserDeposit()
    
    NEW --> VOUCHER_ISSUED: issueVoucher()
    NEW --> CANCELLED: cancelRequest() (after delay)
    
    VOUCHER_ISSUED --> SUCCESSFUL: withdrawFromVoucher() on Dest
    VOUCHER_ISSUED --> CANCELLED: cancelAfterExpiry()
    VOUCHER_ISSUED --> DISPUTE: disputeInsolventXlp()
    VOUCHER_ISSUED --> DISPUTE: disputeVoucherOverride()
    VOUCHER_ISSUED --> UNSPENT: claimUnspentFees()
    
    DISPUTE --> PENALIZED: onXlpSlashedMessage() from L1
    DISPUTE --> VOUCHER_ISSUED: Dispute Fails
    
    PENALIZED --> [*]: Funds Returned to User
    SUCCESSFUL --> [*]: Swap Complete
    CANCELLED --> [*]: Funds Returned
    UNSPENT --> DISPUTE: disputeXlpUnspentVoucherClaim()
    UNSPENT --> [*]: Fees Claimed
    
    note right of NEW
        User locks funds
        and creates request
    end note
    
    note right of VOUCHER_ISSUED
        XLP commits to fulfill
        on destination chain
    end note
    
    note right of SUCCESSFUL
        Assets delivered
        on destination
    end note
    
    note right of DISPUTE
        Challenger initiates
        dispute process
    end note
    
    note right of PENALIZED
        L1 confirms XLP
        misbehavior
    end note
```

---

## Sequence Diagrams

### 1. Happy Path: Cross-Chain Token Transfer

```mermaid
sequenceDiagram
    participant User
    participant Wallet
    participant OriginChain as Origin L2 (Arbitrum)<br/>CrossChainPaymaster
    participant XLP as XLP Off-chain
    participant DestChain as Dest L2 (Optimism)<br/>CrossChainPaymaster
    participant L1 as L1 StakeManager

    Note over User,L1: Setup Phase
    XLP->>L1: stake(chainIds, amounts)
    L1->>L1: Record stake per chain
    XLP->>OriginChain: registerXlp()
    XLP->>DestChain: depositLiquidity(tokens)

    Note over User,L1: Transaction Initiation
    User->>Wallet: Request: Transfer 100 USDC<br/>from Arbitrum to Optimism
    Wallet->>Wallet: Construct multi-chain UserOps
    
    Wallet->>OriginChain: UserOp.execute()<br/>calls lockUserDeposit(voucherRequest)
    activate OriginChain
    OriginChain->>OriginChain: Validate sender & nonce
    OriginChain->>OriginChain: Lock 100 USDC from user
    OriginChain->>OriginChain: Store metadata with status=NEW
    OriginChain-->>XLP: Event: VoucherRequestCreated
    deactivate OriginChain

    Note over XLP: Reverse Dutch Auction Competition
    XLP->>XLP: Calculate optimal fee based on feeRule
    XLP->>XLP: Sign voucher with commitment
    
    XLP->>OriginChain: issueVoucher(voucherRequest, voucher)
    activate OriginChain
    OriginChain->>OriginChain: Verify voucher signature
    OriginChain->>OriginChain: Update status=VOUCHER_ISSUED
    OriginChain->>OriginChain: Record XLP address & timestamp
    OriginChain-->>Wallet: Event: VoucherIssued
    deactivate OriginChain

    Wallet->>Wallet: Detect VoucherIssued event
    Wallet->>Wallet: Attach voucher to dest UserOp

    Wallet->>DestChain: UserOp with paymasterAndData<br/>(contains voucher)
    activate DestChain
    DestChain->>DestChain: _validatePaymasterUserOp()
    DestChain->>DestChain: Verify voucher signature
    DestChain->>DestChain: Check XLP has sufficient balance
    DestChain->>DestChain: Precharge gas from XLP
    DestChain->>User: Transfer 100 USDC to user
    DestChain->>DestChain: Status=SUCCESSFUL
    DestChain->>DestChain: _postOp(): Refund unused gas
    DestChain-->>XLP: Event: VoucherSpent
    deactivate DestChain

    Note over User,L1: Settlement Phase
    XLP->>OriginChain: redeemFulfilledVouchers(voucherIds)
    OriginChain->>OriginChain: Verify unlock delay passed
    OriginChain->>XLP: Transfer original 100 USDC + fees
    
    User->>User: ✅ Transaction Complete!
```

### 2. XLP Insolvency Dispute Flow

```mermaid
sequenceDiagram
    participant User
    participant Challenger as Honest XLP/User
    participant OriginL2 as Origin L2
    participant DestL2 as Dest L2
    participant L1Bridge as L1 Bridge
    participant L1SM as L1 StakeManager
    participant MaliciousXLP as Malicious XLP

    Note over User,MaliciousXLP: XLP Issues Voucher but Cannot Fulfill
    User->>OriginL2: lockUserDeposit(request)
    MaliciousXLP->>OriginL2: issueVoucher(voucher)
    OriginL2->>OriginL2: Status = VOUCHER_ISSUED
    
    User->>DestL2: Submit UserOp with voucher
    DestL2->>DestL2: withdrawFromVoucher()
    DestL2->>DestL2: Check XLP balance
    DestL2->>DestL2: ❌ Insufficient balance!
    DestL2->>User: Revert (voucher invalid)

    Note over Challenger,L1SM: Dispute Initiation on Destination
    Challenger->>DestL2: proveXlpInsolvent(<br/>voucherRequests[],<br/>vouchers[],<br/>chunkIndex, totalChunks)
    activate DestL2
    DestL2->>DestL2: Validate each voucher
    DestL2->>DestL2: Confirm XLP was insolvent
    DestL2->>DestL2: Build ReportProofLeg (destination)
    DestL2->>L1Bridge: sendMessageToL1(proofLeg)
    deactivate DestL2

    Note over Challenger,L1SM: Dispute Initiation on Origin
    Challenger->>OriginL2: disputeInsolventXlp(<br/>disputeVouchers[],<br/>chunkIndex, totalChunks)
    activate OriginL2
    OriginL2->>OriginL2: Require bond payment
    Challenger->>OriginL2: Pay bond (% of disputed amount)
    OriginL2->>OriginL2: Update status = DISPUTE
    OriginL2->>OriginL2: Build ReportDisputeLeg (origin)
    OriginL2->>L1Bridge: sendMessageToL1(disputeLeg)
    deactivate OriginL2

    Note over L1SM: Dispute Resolution on L1
    L1Bridge->>L1SM: reportDestinationProof(proofLeg)
    L1Bridge->>L1SM: reportOriginDispute(disputeLeg)
    
    activate L1SM
    L1SM->>L1SM: Match origin & destination legs
    L1SM->>L1SM: Validate timestamps (dest before origin)
    L1SM->>L1SM: Verify same requestIds
    L1SM->>L1SM: Calculate slash amount
    L1SM->>L1SM: Slash XLP stake
    L1SM->>L1SM: Distribute slashed funds:<br/>- Challenger (bond return + reward)<br/>- Affected users
    L1SM->>OriginL2: sendMessageToL2(slashOutput)
    L1SM->>DestL2: sendMessageToL2(slashOutput)
    deactivate L1SM

    OriginL2->>OriginL2: onXlpSlashedMessage()
    OriginL2->>OriginL2: Update status = PENALIZED
    OriginL2->>User: Refund locked funds

    DestL2->>DestL2: onXlpSlashedMessage()
    DestL2->>DestL2: Mark XLP as slashed

    User->>User: ✅ Funds recovered!
    Challenger->>Challenger: ✅ Reward received!
```

### 3. Voucher Override Dispute Flow

```mermaid
sequenceDiagram
    participant User
    participant XLP1 as XLP 1 (Honest)
    participant XLP2 as XLP 2 (Fast but dishonest)
    participant OriginL2
    participant DestL2
    participant L1

    Note over User,L1: XLP2 issues override voucher to front-run XLP1
    
    User->>OriginL2: lockUserDeposit(allowedXlps=[XLP1])
    OriginL2->>OriginL2: Status = NEW
    
    XLP1->>OriginL2: issueVoucher(voucher1, type=STANDARD)
    OriginL2->>OriginL2: Record XLP1 as issuer, status=VOUCHER_ISSUED
    
    Note over XLP2: XLP2 front-runs on destination
    XLP2->>XLP2: Create voucher2 with type=OVERRIDE<br/>(not allowed by user!)
    XLP2->>DestL2: Direct call to withdrawFromVoucher(voucher2)
    DestL2->>DestL2: Verify signature (valid but unauthorized)
    DestL2->>User: Transfer assets
    DestL2->>DestL2: Status = SUCCESSFUL, paidBy = XLP2

    Note over XLP1: XLP1 discovers the override
    User->>DestL2: Try to use voucher1
    DestL2->>DestL2: ❌ Already fulfilled by XLP2!

    Note over XLP1,L1: Accusation Process
    XLP1->>DestL2: accuseFalseVoucherOverride(<br/>voucherRequest, voucherOverride)
    activate DestL2
    DestL2->>DestL2: Verify XLP1 is registered
    DestL2->>DestL2: Verify voucher2 is type=OVERRIDE
    DestL2->>DestL2: Verify atomicSwap was paid by XLP2 (not XLP1)
    DestL2->>DestL2: Build destination proof leg
    DestL2->>L1: sendMessageToL1(proofLeg)
    deactivate DestL2

    XLP1->>OriginL2: disputeVoucherOverride(<br/>disputeVoucher[], XLP2)
    activate OriginL2
    OriginL2->>OriginL2: Verify original voucher issued by XLP1
    OriginL2->>OriginL2: Build origin dispute leg
    OriginL2->>L1: sendMessageToL1(disputeLeg)
    deactivate OriginL2

    activate L1
    L1->>L1: Match legs for VOUCHER_OVERRIDE dispute
    L1->>L1: Verify XLP2 not in allowedXlps
    L1->>L1: Slash XLP2 stake
    L1->>XLP1: Distribute slashed amount
    L1->>OriginL2: Notify slashing
    deactivate L1

    OriginL2->>OriginL2: Status = PENALIZED
    OriginL2->>XLP1: Refund/Reward

    XLP1->>XLP1: ✅ Justice served!
```

### 4. ERC-4337 Integration Flow

```mermaid
sequenceDiagram
    participant Bundler
    participant EntryPoint as EntryPoint (ERC-4337)
    participant Account as Smart Account
    participant Paymaster as CrossChainPaymaster
    participant XLP

    Note over Bundler,XLP: Validation Phase
    Bundler->>EntryPoint: handleOps([userOp])
    activate EntryPoint
    
    EntryPoint->>Account: validateUserOp(userOp)
    Account->>Account: Verify signature
    Account-->>EntryPoint: validationData
    
    EntryPoint->>Paymaster: validatePaymasterUserOp(userOp)
    activate Paymaster
    
    Paymaster->>Paymaster: Decode paymasterAndData
    Paymaster->>Paymaster: Extract vouchers[] from signature
    Paymaster->>Paymaster: Verify voucher.sender == userOp.sender
    
    loop For each voucher
        Paymaster->>Paymaster: Verify XLP signature on voucher
        Paymaster->>Paymaster: Check XLP has sufficient balance
        Paymaster->>Paymaster: _withdrawFromVoucher()
        Paymaster->>Account: Transfer requested assets
        Paymaster->>Paymaster: Validate minimum amounts
    end
    
    Paymaster->>XLP: Precharge gas from XLP deposit
    Paymaster-->>EntryPoint: context, validationData
    deactivate Paymaster
    
    Note over EntryPoint: Execution Phase
    EntryPoint->>Account: execute(userOp.callData)
    Account->>Account: Perform user's actions
    Account-->>EntryPoint: execution result
    
    Note over EntryPoint: Post-Op Phase
    EntryPoint->>Paymaster: postOp(context, actualGasCost)
    activate Paymaster
    Paymaster->>Paymaster: Calculate actual gas used
    Paymaster->>Paymaster: Refund unused gas to XLP
    Paymaster->>Paymaster: Record final costs
    deactivate Paymaster
    
    EntryPoint-->>Bundler: Transaction complete
    deactivate EntryPoint
```

---

## Bridge Patterns

### Bridge Architecture Overview

```mermaid
graph TB
    subgraph "L1 Bridge Layer"
        L1Arb[L1ArbitrumBridgeConnector]
        L1Opt[L1OptimismBridgeConnector]
        L1Eth[L1EthereumLocalBridge]
        L1Bridge[IL1Bridge Interface]
        
        L1Bridge -.implements.- L1Arb
        L1Bridge -.implements.- L1Opt
        L1Bridge -.implements.- L1Eth
    end

    subgraph "Native Bridge Protocols"
        ArbInbox[Arbitrum Inbox]
        ArbOutbox[Arbitrum Outbox]
        OptPortal[Optimism Portal]
        OptMessenger[L1CrossDomainMessenger]
    end

    subgraph "L2 Bridge Layer"
        L2Arb[L2ArbitrumBridgeConnector]
        L2Opt[L2OptimismBridgeConnector]
        L2Bridge[IL2Bridge Interface]
        
        L2Bridge -.implements.- L2Arb
        L2Bridge -.implements.- L2Opt
    end

    subgraph "EIL Core"
        L1SM[L1AtomicSwapStakeManager]
        OriginPM[Origin CrossChainPaymaster]
        DestPM[Dest CrossChainPaymaster]
    end

    subgraph "Message Envelope Pattern"
        EnvelopeLib[EnvelopeLib]
        Wrapper[BridgeMessengerLib]
    end

    L1SM -->|Pull messages| L1Arb
    L1SM -->|Pull messages| L1Opt
    
    L1Arb <-->|Native protocol| ArbInbox
    L1Arb <-->|Native protocol| ArbOutbox
    L1Opt <-->|Native protocol| OptPortal
    L1Opt <-->|Native protocol| OptMessenger
    
    L2Arb <-->|Native protocol| ArbInbox
    L2Arb <-->|Native protocol| ArbOutbox
    L2Opt <-->|Native protocol| OptPortal
    L2Opt <-->|Native protocol| OptMessenger
    
    OriginPM --> L2Arb
    OriginPM --> L2Opt
    DestPM --> L2Arb
    DestPM --> L2Opt
    
    L1Arb -.uses.- EnvelopeLib
    L1Opt -.uses.- EnvelopeLib
    L2Arb -.uses.- EnvelopeLib
    L2Opt -.uses.- EnvelopeLib
    
    OriginPM -.uses.- Wrapper
    DestPM -.uses.- Wrapper
    L1SM -.uses.- Wrapper

    style EnvelopeLib fill:#ffe1e1
    style L1SM fill:#e1f5ff
```

### Envelope Pattern for Message Security

```mermaid
sequenceDiagram
    participant Sender as Origin Contract
    participant EnvelopeLib
    participant Wrapper as BridgeMessengerLib
    participant Bridge as Bridge Connector
    participant NativeBridge as Native Bridge Protocol
    participant L1 as L1 StakeManager
    
    Note over Sender,L1: L2 to L1 Message Flow
    
    Sender->>EnvelopeLib: encodeEnvelope(fromApp=self, data)
    EnvelopeLib->>EnvelopeLib: envelope = abi.encode(fromApp, data)
    EnvelopeLib-->>Sender: envelope
    
    Sender->>Wrapper: sendMessageToL1Unprotected(to, envelope)
    Wrapper->>Wrapper: wrapper = encodeWrapper(<br/>fromChain, envelope, feeData)
    Wrapper->>Bridge: sendMessageToL1(to, wrapper)
    
    Bridge->>Bridge: Decode wrapper, verify fromApp
    Bridge->>NativeBridge: Protocol-specific send
    
    Note over NativeBridge: Native bridge validates
    
    NativeBridge->>Bridge: forwardFromL2(to, wrapper)
    Bridge->>Bridge: Decode envelope, extract appSender
    Bridge->>Bridge: Store _l2AppSender temporarily
    Bridge->>L1: call(data)
    
    L1->>Bridge: l2AppSender() view call
    Bridge-->>L1: returns stored appSender
    L1->>L1: Verify appSender == expected contract
    L1->>L1: ✅ Process message securely
    
    Bridge->>Bridge: Clear _l2AppSender
    
    Note over Sender,L1: Security: Each layer adds verification<br/>Prevents spoofing of message origin
```

### Bridge Connector Comparison

| Feature | Arbitrum Connector | Optimism Connector | Purpose |
|---------|-------------------|-------------------|---------|
| **L1→L2** | `IArbInbox.createRetryableTicket()` | `IL1CrossDomainMessenger.sendMessage()` | Submit messages from L1 to L2 |
| **L2→L1** | `IArbOutbox.executeTransaction()` | `IOptimismPortal.finalizeWithdrawalTransaction()` | Finalize L2 messages on L1 |
| **Message Format** | `(bytes32[] proof, uint256 index, ...)` | `(WithdrawalTransaction, bytes proof)` | Protocol-specific encoding |
| **Sender Verification** | `outbox.l2ToL1Sender()` | `messenger.xDomainMessageSender()` | Get L2 sender address |
| **Envelope Pattern** | ✅ Yes | ✅ Yes | Add application-layer sender info |
| **Pull Pattern** | `applyL2ToL1Messages(bridgeMessages[])` | `applyL2ToL1Messages(bridgeMessages[])` | Batch process messages |

---

## Dispute Resolution Flows

### Dispute Type Decision Tree

```mermaid
graph TD
    Start[XLP Misbehavior Detected] --> Type{What went wrong?}
    
    Type -->|XLP issued voucher<br/>but had insufficient funds| Insolvent[INSOLVENT_XLP Dispute]
    Type -->|XLP issued override voucher<br/>not authorized by user| Override[VOUCHER_OVERRIDE Dispute]
    Type -->|XLP claimed unspent fees<br/>but voucher was used| UnspentClaim[UNSPENT_VOUCHER_FEE_CLAIM Dispute]
    
    Insolvent --> InsolventSteps[1. User/XLP calls proveXlpInsolvent on Dest<br/>2. Challenger calls disputeInsolventXlp on Origin<br/>3. Post bond + submit vouchers in chunks]
    
    Override --> OverrideSteps[1. Honest XLP calls accuseFalseVoucherOverride on Dest<br/>2. Calls disputeVoucherOverride on Origin<br/>3. Prove original voucher was from allowed XLP]
    
    UnspentClaim --> UnspentSteps[1. User/XLP calls proveVoucherSpent on Dest<br/>2. Calls disputeXlpUnspentVoucherClaim on Origin<br/>3. Prove voucher was actually used]
    
    InsolventSteps --> L1Process[L1 Processing]
    OverrideSteps --> L1Process
    UnspentSteps --> L1Process
    
    L1Process --> MatchLegs{Match Origin<br/>& Dest Legs?}
    
    MatchLegs -->|Yes| ValidateTime{Dest timestamp<br/>before Origin?}
    MatchLegs -->|No| DisputeFails[Dispute Fails]
    
    ValidateTime -->|Yes| SlashXLP[Slash XLP Stake]
    ValidateTime -->|No| DisputeFails
    
    SlashXLP --> Distribute[Distribute Slashed Funds:<br/>1. Return bond to challenger<br/>2. Reward challenger<br/>3. Compensate affected users]
    
    Distribute --> Notify[Notify L2s via bridges]
    Notify --> Complete[Dispute Resolved]
    
    DisputeFails --> ReturnBond[Return bond to XLP]
    
    style Insolvent fill:#ff9999
    style Override fill:#ffcc99
    style UnspentClaim fill:#99ccff
    style SlashXLP fill:#ff6666
    style Complete fill:#99ff99
```

### L1 Dispute Matching Logic

```mermaid
flowchart TD
    Start[L1 Receives Dispute Legs] --> CheckType{Dispute Type}
    
    CheckType -->|INSOLVENT_XLP| InsolvCheck[Check Insolvency Dispute]
    CheckType -->|VOUCHER_OVERRIDE| OverrideCheck[Check Override Dispute]
    CheckType -->|UNSPENT_VOUCHER_FEE_CLAIM| UnspentCheck[Check Unspent Claim]
    
    InsolvCheck --> InsolvDest{Destination<br/>Proof Leg<br/>exists?}
    InsolvDest -->|Yes| InsolvOrig{Origin<br/>Dispute Leg<br/>exists?}
    InsolvDest -->|No| WaitForLeg[Wait for other leg]
    
    InsolvOrig -->|Yes| MatchRequestIds{requestIdsHash<br/>matches?}
    InsolvOrig -->|No| WaitForLeg
    
    MatchRequestIds -->|Yes| CheckTimestamp{destTimestamp<br/>< originTimestamp<br/>- MIN_GAP?}
    MatchRequestIds -->|No| RejectDispute[Reject: Mismatched requests]
    
    CheckTimestamp -->|Yes| ValidateChain{Verify<br/>chain info<br/>registered?}
    CheckTimestamp -->|No| RejectDispute
    
    ValidateChain -->|Yes| CalculateSlash[Calculate Slash Amount]
    ValidateChain -->|No| RejectDispute
    
    CalculateSlash --> DeductStake[Deduct from XLP stake]
    DeductStake --> DistributeFunds[Distribute to:<br/>1. Bond return<br/>2. Challenger reward<br/>3. User compensation<br/>4. Protocol fee]
    
    DistributeFunds --> NotifyL2Origin[Send SlashOutput to Origin L2]
    NotifyL2Origin --> NotifyL2Dest[Send SlashOutput to Dest L2]
    NotifyL2Dest --> UpdateState[Update dispute state = RESOLVED]
    UpdateState --> End[✅ Complete]
    
    OverrideCheck --> SimilarFlow[Similar matching logic<br/>with override-specific checks]
    UnspentCheck --> SimilarFlow
    
    SimilarFlow --> End
    WaitForLeg --> End
    RejectDispute --> End

    style CalculateSlash fill:#ff9999
    style DistributeFunds fill:#99ff99
    style RejectDispute fill:#ffcccc
```

### Stake Management State Machine

```mermaid
stateDiagram-v2
    [*] --> Unstaked: XLP Registers
    
    Unstaked --> Staked: addStake(chainIds[], amounts[])
    
    Staked --> StakeUpdated: addStake() - increase
    StakeUpdated --> Staked
    
    Staked --> UnstakeRequested: requestUnstake(chainId)
    
    UnstakeRequested --> Staked: cancelUnstake()
    UnstakeRequested --> Unstaking: After UNSTAKE_DELAY
    
    Unstaking --> PartiallyUnstaked: withdrawStake(partial)
    PartiallyUnstaked --> Staked: Remaining stake > MIN_STAKE_PER_CHAIN
    PartiallyUnstaked --> Unstaked: Remaining stake == 0
    
    Staked --> Slashed: Dispute resolved against XLP
    Slashed --> Staked: Remaining stake sufficient
    Slashed --> Frozen: Stake < MIN_STAKE_PER_CHAIN
    
    Frozen --> Staked: addStake() to restore
    Frozen --> Unstaked: Complete withdrawal
    
    note right of Staked
        Active XLP providing liquidity
        Can fulfill vouchers
    end note
    
    note right of UnstakeRequested
        Waiting period to ensure
        no pending disputes
    end note
    
    note right of Slashed
        Penalties applied from
        dispute resolution
    end note
```

---

## Trust Model

### Security Guarantees & Assumptions

```mermaid
graph TB
    subgraph "User Guarantees"
        U1[✅ Self-custody at all times]
        U2[✅ Funds locked on-chain, not with XLP]
        U3[✅ Can dispute & recover if XLP fails]
        U4[✅ No off-chain trust needed]
        U5[✅ Censorship resistant]
    end

    subgraph "XLP Incentives"
        X1[💰 Earn fees for liquidity]
        X2[⚡ Compete on speed & price]
        X3[🔒 Stake at risk if dishonest]
        X4[📊 Reputation matters]
    end

    subgraph "System Assumptions"
        S1[🔗 L1 ↔ L2 bridges are secure]
        S2[⏱️ Disputes can be raised within time limits]
        S3[💵 XLP stake covers liabilities]
        S4[👥 At least one honest challenger exists]
        S5[⛽ Gas costs reasonable for disputes]
    end

    subgraph "Attack Mitigations"
        A1[🛡️ Voucher Override: Require allowlist]
        A2[🛡️ Insolvency: Stake slashing]
        A3[🛡️ Front-running: Signature verification]
        A4[🛡️ Griefing: Dispute bonds]
        A5[🛡️ Spam: Gas costs & time locks]
    end

    U3 --> X3
    X3 --> S3
    S4 --> A2
    A4 --> S5

    style U1 fill:#ccffcc
    style U2 fill:#ccffcc
    style U3 fill:#ccffcc
    style X3 fill:#ffcccc
    style A2 fill:#ffcccc
```

### Attack Surface Analysis

| Attack Vector | Mitigation | Code Location |
|---------------|------------|---------------|
| **XLP issues voucher but doesn't fulfill** | Insolvency dispute → stake slashing | `DestinationSwapDisputeManager.proveXlpInsolvent()` |
| **XLP issues override voucher** | Allowlist check + override dispute | `OriginationSwapDisputeManager.disputeVoucherOverride()` |
| **XLP front-runs user's voucher** | Signature verification, user controls allowlist | `CrossChainPaymaster._validatePaymasterUserOp()` |
| **XLP claims unspent fees dishonestly** | Proof of spending on destination chain | `DestinationSwapDisputeManager.proveVoucherSpent()` |
| **Malicious user disputes valid voucher** | Dispute bond requirement, bond slashed if invalid | `OriginSwapBase._initiateDisputeWithBond()` |
| **Bridge message spoofing** | Envelope pattern with app sender verification | `EnvelopeLib.sol`, `L1Bridge.forwardFromL2()` |
| **Replay attacks** | Nonce tracking per user | `OriginSwapManager.lockUserDeposit()` |
| **Griefing via spam disputes** | Bond requirement + gas costs | All dispute functions |
| **XLP withdraw stake with pending liabilities** | Unstake delay + dispute window | `L1AtomicSwapStakeManager.requestUnstake()` |

---

## Advanced Patterns

### Gas Accounting Pattern

```mermaid
sequenceDiagram
    participant User
    participant Paymaster as CrossChainPaymaster
    participant XLP
    participant EntryPoint

    Note over User,EntryPoint: Pre-charge Pattern
    
    EntryPoint->>Paymaster: validatePaymasterUserOp(userOp)
    activate Paymaster
    
    Paymaster->>Paymaster: maxCost = userOp.maxGas * maxFeePerGas
    Paymaster->>Paymaster: _preChargeXlpGas(xlp, maxCost)
    
    Paymaster->>Paymaster: xlpGasDeposit[xlp] -= maxCost
    Paymaster->>Paymaster: Store context: (xlp, maxCost)
    
    Paymaster-->>EntryPoint: context, validationData
    deactivate Paymaster
    
    Note over EntryPoint: Execution happens...
    
    EntryPoint->>Paymaster: postOp(context, actualGasCost)
    activate Paymaster
    
    Paymaster->>Paymaster: (xlp, maxCost) = decode(context)
    Paymaster->>Paymaster: actualCost = actualGasCost + POST_OP_GAS_COST
    Paymaster->>Paymaster: refund = maxCost - actualCost
    
    Paymaster->>Paymaster: xlpGasDeposit[xlp] += refund
    Paymaster->>Paymaster: Emit GasRefunded(xlp, refund)
    
    deactivate Paymaster
    
    Note over XLP: XLP can withdraw deposits anytime
    XLP->>Paymaster: withdrawGasDeposit(amount)
    Paymaster->>XLP: Transfer native token
```

### Token Deposit Management

```mermaid
graph LR
    subgraph "XLP Deposits on Destination Chain"
        Deposit[depositFor XLP]
        Registry[(xlpDeposits mapping)]
        Withdraw[_transferOutAssetsDecrementDeposit]
    end

    subgraph "User Requests"
        VoucherReq[Voucher Request:<br/>100 USDC needed]
    end

    subgraph "Validation"
        Check{XLP has<br/>≥100 USDC?}
    end

    XLP -->|depositLiquidity| Deposit
    Deposit -->|Update balance| Registry
    
    VoucherReq --> Check
    Registry -.->|Query balance| Check
    
    Check -->|Yes| Withdraw
    Check -->|No| Revert[❌ Insufficient liquidity]
    
    Withdraw -->|Decrement| Registry
    Withdraw -->|Transfer| User
    
    style Check fill:#ffffcc
    style Revert fill:#ffcccc
    style User fill:#ccffcc
```

### Chunked Reporting for Large Disputes

```mermaid
sequenceDiagram
    participant Challenger
    participant OriginL2
    participant L1
    
    Note over Challenger,L1: Dispute 1000 vouchers (too large for 1 tx)
    
    Challenger->>Challenger: Split into chunks:<br/>Chunk 0: vouchers[0-99]<br/>Chunk 1: vouchers[100-199]<br/>...<br/>Chunk 9: vouchers[900-999]
    
    Challenger->>Challenger: Calculate committedRequestIdsHash<br/>= hash(all 1000 requestIds)
    
    loop For each chunk
        Challenger->>OriginL2: disputeInsolventXlp(<br/>chunk, chunkIndex,<br/>totalChunks=10,<br/>committedHash)
        
        activate OriginL2
        OriginL2->>OriginL2: Validate chunk vouchers
        OriginL2->>OriginL2: Accumulate requestIds
        OriginL2->>OriginL2: Increment receivedChunks
        
        alt Last chunk received
            OriginL2->>OriginL2: hash(accumulated) == committedHash?
            OriginL2->>OriginL2: ✅ Complete report
            OriginL2->>L1: Send dispute leg with all requestIds
        else More chunks expected
            OriginL2->>OriginL2: Wait for next chunk
        end
        deactivate OriginL2
    end
    
    Note over Challenger,L1: Security: Prevents partial/incomplete disputes<br/>Commitment ensures all chunks belong to same dispute
```

---

## Key Insights for Backend Engineers

### 1. **Off-chain XLP Service Requirements**
- **Event Monitoring**: Listen for `VoucherRequestCreated` events across all chains
- **Fee Calculation**: Implement reverse dutch auction logic based on `AtomicSwapFeeRule`
- **Signature Generation**: Sign vouchers with EIP-712 standard
- **Liquidity Management**: Track deposits across chains, rebalance as needed
- **Dispute Detection**: Monitor for insolvency, override attacks, false claims
- **Cross-chain Coordination**: Ensure sufficient stake on L1 covers all chains

### 2. **Critical Security Considerations**
- **Nonce Management**: User nonces prevent replay; XLP must track latest nonce
- **Time Windows**: 
  - Voucher expiration times
  - Dispute windows
  - Unstake delays
  - Unlock delays for redemption
- **Signature Verification**: Both user and XLP signatures must be validated
- **Allowlist Enforcement**: Only authorized XLPs can fulfill requests

### 3. **Gas Optimization Patterns**
- **Batch Processing**: Multiple vouchers in single transaction
- **Chunked Reporting**: Large dispute sets split to fit block gas limits
- **Pre-charge/Post-op**: ERC-4337 pattern for accurate gas accounting
- **Storage Optimization**: EnumerableMap for efficient XLP lookups

### 4. **Integration Points**
- **ERC-4337 Bundler**: Submit UserOps with paymaster data
- **Bridge Watchers**: Monitor L1↔L2 message finalization
- **Price Oracles**: Calculate optimal fees based on market conditions
- **Liquidity Providers**: API for XLPs to register, stake, deposit

### 5. **Testing Scenarios**
- Happy path: User → Origin → XLP → Destination → Success
- XLP insolvency during high demand
- Multiple XLPs competing for same request
- Override attack by malicious XLP
- Dispute resolution with L1 finalization
- Bridge message delays/reorgs
- Gas price volatility during execution

---

## Summary

The EIL protocol implements a sophisticated cross-chain swap system with:

1. **Trust-minimized design**: On-chain enforcement, no relayer trust
2. **Economic security**: XLP stake on L1 backs all commitments  
3. **Dispute resolution**: Three-way matching (origin dispute + destination proof + L1 arbitration)
4. **Bridge abstraction**: Pluggable connectors for Arbitrum, Optimism, etc.
5. **ERC-4337 integration**: Gasless UX via paymaster pattern
6. **Modular architecture**: Delegation pattern keeps contracts under size limit

**For backend engineers**, the key is understanding:
- Event-driven XLP services
- Multi-chain state synchronization  
- Cryptographic proof generation
- Economic incentive alignment
- Gas-efficient batch operations

This architecture enables seamless cross-L2 interactions while preserving Ethereum's core values of decentralization and user sovereignty.
