# EIL Smart Contract Interaction Guide

## Overview

This guide provides practical code examples for interacting with EIL contracts as a backend engineer building services for XLPs, users, or challengers.

---

## Table of Contents

1. [XLP Service Implementation](#xlp-service-implementation)
2. [User Wallet Integration](#user-wallet-integration)
3. [Challenger/Disputer Implementation](#challengerdisputer-implementation)
4. [Event Monitoring](#event-monitoring)
5. [Testing Strategies](#testing-strategies)

---

## XLP Service Implementation

### 1. Initial Setup: Staking & Registration

```typescript
import { ethers } from 'ethers';

class XLPService {
  private l1StakeManager: Contract;
  private l2Paymasters: Map<number, Contract>; // chainId -> paymaster
  private signingKey: Wallet;
  
  /**
   * Step 1: Stake on L1 for multiple chains
   */
  async stakeOnL1(chainsConfig: ChainStakeConfig[]) {
    const chainIds = chainsConfig.map(c => c.chainId);
    const amounts = chainsConfig.map(c => c.stakeAmount);
    
    // Prepare chain info for each chain
    const chainsInfo = await Promise.all(
      chainsConfig.map(async (config) => ({
        chainId: config.chainId,
        bridgeConnector: config.l1BridgeConnector,
        paymasterOnOriginChain: config.paymasterAddress,
        paymasterOnDestinationChain: config.paymasterAddress,
        l2ToL1GasLimit: 1000000, // Adjust per chain
      }))
    );
    
    // Calculate total ETH needed
    const totalStake = amounts.reduce((a, b) => a.add(b), ethers.BigNumber.from(0));
    
    // Execute stake transaction
    const tx = await this.l1StakeManager.addChainsInfo(
      chainIds,
      chainsInfo,
      { value: totalStake }
    );
    
    await tx.wait();
    console.log(`✅ Staked ${ethers.utils.formatEther(totalStake)} ETH across ${chainIds.length} chains`);
  }
  
  /**
   * Step 2: Register XLP on each L2
   */
  async registerOnL2(chainId: number, l1XlpAddress: string) {
    const paymaster = this.l2Paymasters.get(chainId);
    
    const tx = await paymaster.registerXlp(l1XlpAddress);
    await tx.wait();
    
    console.log(`✅ Registered XLP on chain ${chainId}`);
  }
  
  /**
   * Step 3: Deposit liquidity on destination chains
   */
  async depositLiquidity(
    chainId: number,
    tokens: { address: string, amount: BigNumber }[]
  ) {
    const paymaster = this.l2Paymasters.get(chainId);
    
    // Approve tokens first
    for (const token of tokens) {
      if (token.address !== ethers.constants.AddressZero) {
        const erc20 = new Contract(token.address, ERC20_ABI, this.signingKey);
        const approveTx = await erc20.approve(paymaster.address, token.amount);
        await approveTx.wait();
      }
    }
    
    // Deposit assets and gas
    const assets = tokens.map(t => ({
      token: t.address,
      amount: t.amount
    }));
    
    const gasDepositAmount = ethers.utils.parseEther('0.1'); // 0.1 ETH for gas
    
    const tx = await paymaster.depositLiquidityAndGas(
      assets,
      { value: gasDepositAmount }
    );
    
    await tx.wait();
    console.log(`✅ Deposited liquidity on chain ${chainId}`);
  }
}

interface ChainStakeConfig {
  chainId: number;
  stakeAmount: BigNumber;
  l1BridgeConnector: string;
  paymasterAddress: string;
}
```

### 2. Monitoring and Issuing Vouchers

```typescript
class VoucherIssuanceService {
  private originPaymasters: Map<number, Contract>;
  private db: Database;
  
  /**
   * Monitor VoucherRequestCreated events across all origin chains
   */
  async startMonitoring() {
    for (const [chainId, paymaster] of this.originPaymasters) {
      const filter = paymaster.filters.VoucherRequestCreated();
      
      paymaster.on(filter, async (
        requestId: string,
        sender: string,
        voucherRequest: any,
        event: Event
      ) => {
        await this.handleVoucherRequest(
          chainId,
          requestId,
          voucherRequest,
          event
        );
      });
      
      console.log(`👀 Monitoring voucher requests on chain ${chainId}`);
    }
  }
  
  /**
   * Evaluate and potentially issue voucher
   */
  private async handleVoucherRequest(
    originChainId: number,
    requestId: string,
    voucherRequest: VoucherRequest,
    event: Event
  ) {
    console.log(`📨 New voucher request: ${requestId}`);
    
    // 1. Check if we're allowed
    const xlpAddress = await this.getL2XlpAddress(originChainId);
    if (!voucherRequest.origination.allowedXlps.includes(xlpAddress)) {
      console.log(`⏭️  Not in allowlist for ${requestId}`);
      return;
    }
    
    // 2. Calculate fee based on reverse dutch auction
    const optimalFee = this.calculateOptimalFee(
      voucherRequest,
      event.blockNumber
    );
    
    // 3. Check if profitable
    if (!this.isProfitable(voucherRequest, optimalFee)) {
      console.log(`💸 Not profitable for ${requestId}`);
      return;
    }
    
    // 4. Verify we have liquidity on destination
    const hasLiquidity = await this.checkDestinationLiquidity(
      voucherRequest.destination.chainId,
      voucherRequest.destination.assets
    );
    
    if (!hasLiquidity) {
      console.log(`💧 Insufficient liquidity for ${requestId}`);
      return;
    }
    
    // 5. Issue voucher!
    await this.issueVoucher(originChainId, requestId, voucherRequest);
  }
  
  /**
   * Calculate optimal fee using reverse dutch auction
   */
  private calculateOptimalFee(
    voucherRequest: VoucherRequest,
    currentBlock: number
  ): BigNumber {
    const feeRule = voucherRequest.origination.feeRule;
    
    // Time elapsed since request creation
    const elapsedBlocks = currentBlock - voucherRequest.creationBlock;
    const elapsedTime = elapsedBlocks * 12; // ~12s per block
    
    // Dutch auction: fee decreases over time
    // fee = startFee - (startFee - endFee) * (elapsed / duration)
    const totalDuration = feeRule.duration;
    const progress = Math.min(elapsedTime / totalDuration, 1);
    
    const feeRange = feeRule.startFee.sub(feeRule.endFee);
    const discount = feeRange.mul(Math.floor(progress * 10000)).div(10000);
    
    return feeRule.startFee.sub(discount);
  }
  
  /**
   * Issue voucher by signing and submitting
   */
  private async issueVoucher(
    originChainId: number,
    requestId: string,
    voucherRequest: VoucherRequest
  ) {
    const paymaster = this.originPaymasters.get(originChainId);
    const xlpAddress = await this.getL2XlpAddress(originChainId);
    
    // 1. Create voucher struct
    const expiresAt = Math.floor(Date.now() / 1000) + (15 * 60); // 15 min
    
    const voucher = {
      requestId: requestId,
      originationXlpAddress: xlpAddress,
      voucherRequestDest: voucherRequest.destination,
      expiresAt: expiresAt,
      voucherType: 0, // STANDARD
      xlpSignature: '0x' // Will be filled
    };
    
    // 2. Sign voucher (EIP-712)
    const signature = await this.signVoucher(voucher, originChainId);
    voucher.xlpSignature = signature;
    
    // 3. Submit to origin chain
    const tx = await paymaster.issueVouchers([{
      voucher: voucher,
      voucherRequest: voucherRequest
    }]);
    
    await tx.wait();
    
    console.log(`✅ Issued voucher for ${requestId}`);
    
    // 4. Store in database for tracking
    await this.db.storeIssuedVoucher({
      requestId,
      originChainId,
      destChainId: voucherRequest.destination.chainId,
      expiresAt,
      status: 'ISSUED'
    });
  }
  
  /**
   * EIP-712 voucher signing
   */
  private async signVoucher(
    voucher: AtomicSwapVoucher,
    chainId: number
  ): Promise<string> {
    const domain = {
      name: 'CrossChainPaymaster',
      version: '1',
      chainId: chainId,
      verifyingContract: this.originPaymasters.get(chainId).address
    };
    
    const types = {
      AtomicSwapVoucher: [
        { name: 'requestId', type: 'bytes32' },
        { name: 'originationXlpAddress', type: 'address' },
        { name: 'voucherRequestDest', type: 'DestinationSwapComponent' },
        { name: 'expiresAt', type: 'uint256' },
        { name: 'voucherType', type: 'uint8' }
      ],
      DestinationSwapComponent: [
        { name: 'chainId', type: 'uint256' },
        { name: 'paymaster', type: 'address' },
        { name: 'sender', type: 'address' },
        { name: 'assets', type: 'Asset[]' },
        { name: 'maxUserOpCost', type: 'uint256' },
        { name: 'expiresAt', type: 'uint256' }
      ],
      Asset: [
        { name: 'token', type: 'address' },
        { name: 'amount', type: 'uint256' }
      ]
    };
    
    const value = {
      requestId: voucher.requestId,
      originationXlpAddress: voucher.originationXlpAddress,
      voucherRequestDest: voucher.voucherRequestDest,
      expiresAt: voucher.expiresAt,
      voucherType: voucher.voucherType
    };
    
    return await this.signingKey._signTypedData(domain, types, value);
  }
}
```

### 3. Redemption After Fulfillment

```typescript
class VoucherRedemptionService {
  /**
   * Monitor voucher spending on destination chains
   */
  async monitorVoucherSpending() {
    for (const [chainId, paymaster] of this.destPaymasters) {
      const filter = paymaster.filters.VoucherSpent();
      
      paymaster.on(filter, async (
        requestId: string,
        sender: string,
        xlpAddress: string,
        event: Event
      ) => {
        if (xlpAddress.toLowerCase() === this.xlpAddress.toLowerCase()) {
          await this.markForRedemption(requestId, chainId);
        }
      });
    }
  }
  
  /**
   * Batch redeem fulfilled vouchers on origin chain
   */
  async redeemFulfilledVouchers(originChainId: number) {
    // Get fulfilled vouchers that passed unlock delay
    const readyVouchers = await this.db.getRedeemableVouchers(
      originChainId,
      Date.now()
    );
    
    if (readyVouchers.length === 0) {
      return;
    }
    
    console.log(`💰 Redeeming ${readyVouchers.length} vouchers on chain ${originChainId}`);
    
    const paymaster = this.originPaymasters.get(originChainId);
    const requestIds = readyVouchers.map(v => v.requestId);
    
    const tx = await paymaster.redeemFulfilledVouchers(requestIds);
    await tx.wait();
    
    // Calculate total redeemed
    const totalRedeemed = readyVouchers.reduce(
      (sum, v) => sum.add(v.amount),
      ethers.BigNumber.from(0)
    );
    
    console.log(`✅ Redeemed ${ethers.utils.formatEther(totalRedeemed)} worth of assets`);
    
    // Update database
    await this.db.markVouchersRedeemed(requestIds);
  }
  
  /**
   * Claim unspent voucher fees (if user never used voucher)
   */
  async claimUnspentFees(originChainId: number) {
    const expiredVouchers = await this.db.getExpiredUnspentVouchers(
      originChainId,
      Date.now()
    );
    
    if (expiredVouchers.length === 0) {
      return;
    }
    
    console.log(`🎁 Claiming fees for ${expiredVouchers.length} unspent vouchers`);
    
    const paymaster = this.originPaymasters.get(originChainId);
    const requestIds = expiredVouchers.map(v => v.requestId);
    
    const tx = await paymaster.claimUnspentVoucherFees(requestIds);
    await tx.wait();
    
    console.log(`✅ Claimed unspent fees`);
  }
}
```

---

## User Wallet Integration

### Creating Cross-Chain UserOperations

```typescript
import { UserOperationBuilder } from '@account-abstraction/sdk';

class CrossChainWallet {
  private account: Contract; // ERC-4337 smart account
  private bundler: BundlerClient;
  
  /**
   * Create cross-chain transaction: Transfer USDC from Arbitrum to Optimism
   */
  async transferCrossChain(
    fromChain: number,    // Arbitrum
    toChain: number,      // Optimism
    token: string,        // USDC address
    amount: BigNumber,    // 100 USDC
    allowedXlps: string[] // Trusted XLPs
  ): Promise<string> {
    
    // 1. Create voucher request
    const voucherRequest = this.createVoucherRequest(
      fromChain,
      toChain,
      token,
      amount,
      allowedXlps
    );
    
    // 2. Create UserOp for origin chain (Arbitrum)
    const originUserOp = await this.createOriginUserOp(
      fromChain,
      voucherRequest
    );
    
    // 3. Submit origin UserOp and wait for voucher
    const originTxHash = await this.bundler.sendUserOperation(
      originUserOp,
      fromChain
    );
    
    console.log(`📤 Origin tx submitted: ${originTxHash}`);
    
    // 4. Wait for VoucherIssued event
    const voucher = await this.waitForVoucher(
      fromChain,
      voucherRequest.requestId
    );
    
    console.log(`🎫 Voucher received from XLP: ${voucher.originationXlpAddress}`);
    
    // 5. Create UserOp for destination chain (Optimism)
    const destUserOp = await this.createDestinationUserOp(
      toChain,
      voucherRequest,
      voucher
    );
    
    // 6. Submit destination UserOp
    const destTxHash = await this.bundler.sendUserOperation(
      destUserOp,
      toChain
    );
    
    console.log(`📥 Destination tx submitted: ${destTxHash}`);
    console.log(`✅ Cross-chain transfer complete!`);
    
    return destTxHash;
  }
  
  /**
   * Create voucher request structure
   */
  private createVoucherRequest(
    fromChain: number,
    toChain: number,
    token: string,
    amount: BigNumber,
    allowedXlps: string[]
  ): VoucherRequest {
    const nonce = await this.getNextNonce(fromChain);
    const originPaymaster = this.getPaymasterAddress(fromChain);
    const destPaymaster = this.getPaymasterAddress(toChain);
    
    return {
      origination: {
        chainId: fromChain,
        paymaster: originPaymaster,
        sender: this.account.address,
        assets: [{ token, amount }],
        feeRule: {
          startFee: amount.mul(3).div(1000), // 0.3% start
          endFee: amount.mul(1).div(1000),   // 0.1% end
          duration: 300, // 5 minutes
          bondType: 0    // PERCENT
        },
        senderNonce: nonce,
        allowedXlps: allowedXlps
      },
      destination: {
        chainId: toChain,
        paymaster: destPaymaster,
        sender: this.account.address,
        assets: [{ 
          token: this.getTokenOnChain(token, toChain), 
          amount 
        }],
        maxUserOpCost: ethers.utils.parseEther('0.01'), // 0.01 ETH gas budget
        expiresAt: Math.floor(Date.now() / 1000) + 3600 // 1 hour
      }
    };
  }
  
  /**
   * Create origin chain UserOp that locks funds
   */
  private async createOriginUserOp(
    chainId: number,
    voucherRequest: VoucherRequest
  ): Promise<UserOperation> {
    const paymaster = this.getPaymasterAddress(chainId);
    
    // Encode call to approve token and lock deposit
    const callData = this.account.interface.encodeFunctionData('execute', [
      paymaster,
      0,
      paymaster.interface.encodeFunctionData('lockUserDeposit', [
        voucherRequest
      ])
    ]);
    
    const builder = new UserOperationBuilder()
      .setSender(this.account.address)
      .setNonce(await this.account.getNonce())
      .setCallData(callData)
      .setCallGasLimit(500000)
      .setVerificationGasLimit(500000)
      .setPreVerificationGas(50000);
    
    // No paymaster on origin (user pays their own gas)
    const userOp = await builder.buildOp(
      this.entryPoint.address,
      chainId
    );
    
    // Sign
    const signature = await this.signUserOp(userOp, chainId);
    userOp.signature = signature;
    
    return userOp;
  }
  
  /**
   * Wait for voucher issuance
   */
  private async waitForVoucher(
    chainId: number,
    requestId: string,
    timeoutMs: number = 300000 // 5 min
  ): Promise<AtomicSwapVoucher> {
    return new Promise((resolve, reject) => {
      const paymaster = this.getPaymaster(chainId);
      const filter = paymaster.filters.VoucherIssued(requestId);
      
      const timeout = setTimeout(() => {
        reject(new Error('Voucher timeout'));
      }, timeoutMs);
      
      paymaster.once(filter, (
        reqId: string,
        xlpAddress: string,
        voucher: any
      ) => {
        clearTimeout(timeout);
        resolve(voucher);
      });
    });
  }
  
  /**
   * Create destination chain UserOp with voucher
   */
  private async createDestinationUserOp(
    chainId: number,
    voucherRequest: VoucherRequest,
    voucher: AtomicSwapVoucher
  ): Promise<UserOperation> {
    const paymaster = this.getPaymasterAddress(chainId);
    
    // User's actual call on destination (could be anything!)
    const callData = this.account.interface.encodeFunctionData('execute', [
      // Example: swap USDC for ETH on Uniswap
      UNISWAP_ROUTER,
      0,
      uniswapRouter.interface.encodeFunctionData('swapExactTokensForETH', [
        voucherRequest.destination.assets[0].amount,
        0, // minAmountOut
        [USDC_ADDRESS, WETH_ADDRESS],
        this.account.address,
        Math.floor(Date.now() / 1000) + 1800
      ])
    ]);
    
    // Encode paymaster data
    const voucherRequestsData = {
      vouchersAssetsMinimums: [
        voucherRequest.destination.assets // Minimum amounts expected
      ]
    };
    
    const paymasterSignature = ethers.utils.defaultAbiCoder.encode(
      ['tuple(bytes32,address,tuple(uint256,address,address,tuple(address,uint256)[],uint256,uint256),uint256,uint8,bytes)[]', 'tuple(bytes)'],
      [
        [voucher], // Array of vouchers
        [ethers.utils.arrayify('0x')] // Session data (empty)
      ]
    );
    
    const paymasterAndData = ethers.utils.hexConcat([
      paymaster,
      ethers.utils.defaultAbiCoder.encode(
        ['tuple(tuple(address,uint256)[][])'],
        [voucherRequestsData]
      ),
      paymasterSignature
    ]);
    
    const builder = new UserOperationBuilder()
      .setSender(this.account.address)
      .setNonce(await this.account.getNonce())
      .setCallData(callData)
      .setPaymasterAndData(paymasterAndData)
      .setCallGasLimit(800000)
      .setVerificationGasLimit(800000)
      .setPreVerificationGas(50000);
    
    const userOp = await builder.buildOp(
      this.entryPoint.address,
      chainId
    );
    
    const signature = await this.signUserOp(userOp, chainId);
    userOp.signature = signature;
    
    return userOp;
  }
}
```

---

## Challenger/Disputer Implementation

### Monitoring for Insolvent XLPs

```typescript
class DisputeMonitorService {
  /**
   * Monitor destination chains for failed voucher redemptions
   */
  async monitorDestinationChain(chainId: number) {
    const paymaster = this.destPaymasters.get(chainId);
    
    // Watch for UserOp reverts due to insufficient XLP balance
    const entryPoint = this.getEntryPoint(chainId);
    const filter = entryPoint.filters.UserOperationRevertReason();
    
    entryPoint.on(filter, async (
      userOpHash: string,
      sender: string,
      nonce: BigNumber,
      revertReason: string,
      event: Event
    ) => {
      // Check if revert was due to voucher validation failure
      if (revertReason.includes('InsufficientXlpBalance')) {
        await this.investigatePotentialInsolvency(
          chainId,
          userOpHash,
          sender,
          event
        );
      }
    });
  }
  
  /**
   * Investigate and potentially dispute insolvent XLP
   */
  private async investigatePotentialInsolvency(
    destChainId: number,
    userOpHash: string,
    sender: string,
    event: Event
  ) {
    // 1. Get the failed UserOp from bundler/mempool
    const userOp = await this.bundler.getUserOpByHash(userOpHash);
    
    // 2. Extract voucher from paymasterAndData
    const voucher = this.extractVoucherFromUserOp(userOp);
    
    // 3. Get original voucher request from origin chain
    const originChainId = await this.getOriginChainId(voucher.requestId);
    const voucherRequest = await this.getVoucherRequest(
      originChainId,
      voucher.requestId
    );
    
    // 4. Verify XLP is indeed insolvent
    const xlpBalance = await this.getXlpBalance(
      destChainId,
      voucher.originationXlpAddress,
      voucherRequest.destination.assets
    );
    
    const requiredBalance = voucherRequest.destination.assets.reduce(
      (sum, asset) => sum.add(asset.amount),
      ethers.BigNumber.from(0)
    );
    
    if (xlpBalance.lt(requiredBalance)) {
      console.log(`🚨 Insolvent XLP detected: ${voucher.originationXlpAddress}`);
      
      // 5. Collect more evidence (other failed vouchers from same XLP)
      const relatedVouchers = await this.findRelatedInsolventVouchers(
        destChainId,
        voucher.originationXlpAddress
      );
      
      // 6. Initiate dispute
      await this.disputeInsolventXlp(
        originChainId,
        destChainId,
        voucher,
        voucherRequest,
        relatedVouchers
      );
    }
  }
  
  /**
   * Submit insolvency dispute
   */
  private async disputeInsolventXlp(
    originChainId: number,
    destChainId: number,
    primaryVoucher: AtomicSwapVoucher,
    primaryRequest: VoucherRequest,
    relatedVouchers: Array<{ voucher: AtomicSwapVoucher, request: VoucherRequest }>
  ) {
    // Combine all vouchers
    const allVouchers = [
      { voucher: primaryVoucher, request: primaryRequest },
      ...relatedVouchers
    ];
    
    // Split into chunks if needed (max vouchers per tx)
    const chunks = this.chunkArray(allVouchers, 50);
    const totalChunks = chunks.length;
    
    // Calculate bond required
    const totalValue = allVouchers.reduce((sum, v) => {
      return sum.add(
        v.request.destination.assets.reduce(
          (assetSum, asset) => assetSum.add(asset.amount),
          ethers.BigNumber.from(0)
        )
      );
    }, ethers.BigNumber.from(0));
    
    const bondPercent = await this.originPaymaster.DISPUTE_BOND_PERCENT();
    const bond = totalValue.mul(bondPercent).div(10000);
    
    console.log(`💰 Dispute bond required: ${ethers.utils.formatEther(bond)} ETH`);
    
    // Generate commitment hash for all requestIds
    const allRequestIds = allVouchers.map(v => v.voucher.requestId);
    const committedHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(['bytes32[]'], [allRequestIds])
    );
    
    // 1. Submit proof on destination chain (each chunk)
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const destPaymaster = this.destPaymasters.get(destChainId);
      
      const tx = await destPaymaster.proveXlpInsolvent(
        chunk.map(v => v.request),
        chunk.map(v => v.voucher),
        this.beneficiaryAddress,
        i, // chunkIndex
        totalChunks,
        Date.now(), // nonce
        committedHash,
        allVouchers.length
      );
      
      await tx.wait();
      console.log(`✅ Submitted dest proof chunk ${i + 1}/${totalChunks}`);
    }
    
    // 2. Submit dispute on origin chain (each chunk)
    const originPaymaster = this.originPaymasters.get(originChainId);
    
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      
      const disputeVouchers = chunk.map(v => ({
        voucherRequest: v.request,
        voucher: v.voucher
      }));
      
      const tx = await originPaymaster.disputeInsolventXlp(
        disputeVouchers,
        [], // altVouchers (alternative XLP vouchers)
        primaryVoucher.originationXlpAddress,
        this.beneficiaryAddress,
        i,
        totalChunks,
        Date.now(),
        committedHash,
        allVouchers.length,
        { value: i === 0 ? bond : 0 } // Pay bond on first chunk
      );
      
      await tx.wait();
      console.log(`✅ Submitted origin dispute chunk ${i + 1}/${totalChunks}`);
    }
    
    console.log(`🎯 Dispute submitted! Waiting for L1 resolution...`);
    
    // 3. Monitor L1 for slash confirmation
    await this.monitorDisputeResolution(
      primaryVoucher.originationXlpAddress,
      originChainId,
      destChainId
    );
  }
  
  /**
   * Monitor L1 for dispute resolution
   */
  private async monitorDisputeResolution(
    xlpAddress: string,
    originChain: number,
    destChain: number
  ) {
    const l1StakeManager = this.l1StakeManager;
    const filter = l1StakeManager.filters.XlpSlashed(
      xlpAddress,
      originChain,
      destChain
    );
    
    return new Promise((resolve) => {
      l1StakeManager.once(filter, async (
        xlp: string,
        orig: number,
        dest: number,
        amount: BigNumber,
        event: Event
      ) => {
        console.log(`✅ XLP ${xlp} slashed! Amount: ${ethers.utils.formatEther(amount)}`);
        
        // Verify we received our reward
        const slashEvent = await this.parseSlashEvent(event);
        console.log(`💰 Challenger reward: ${ethers.utils.formatEther(slashEvent.challengerReward)}`);
        
        resolve(slashEvent);
      });
    });
  }
}
```

### Disputing False Override Vouchers

```typescript
class OverrideDisputeService {
  /**
   * Detect unauthorized override vouchers
   */
  async detectOverrideVouchers(destChainId: number) {
    const paymaster = this.destPaymasters.get(destChainId);
    const filter = paymaster.filters.VoucherSpent();
    
    paymaster.on(filter, async (
      requestId: string,
      sender: string,
      xlpAddress: string,
      expiresAt: number,
      voucherType: number,
      event: Event
    ) => {
      // Check if it was an OVERRIDE type voucher
      if (voucherType === 1) { // OVERRIDE
        await this.investigateOverride(
          destChainId,
          requestId,
          xlpAddress,
          event
        );
      }
    });
  }
  
  /**
   * Investigate override voucher authorization
   */
  private async investigateOverride(
    destChainId: number,
    requestId: string,
    xlpAddress: string,
    event: Event
  ) {
    // 1. Get original request from origin chain
    const originChainId = await this.getOriginChainId(requestId);
    const voucherRequest = await this.getVoucherRequest(
      originChainId,
      requestId
    );
    
    // 2. Check if XLP was in allowed list
    if (!voucherRequest.origination.allowedXlps.includes(xlpAddress)) {
      console.log(`🚨 Unauthorized override by ${xlpAddress}!`);
      
      // 3. Get the actual override voucher
      const overrideVoucher = await this.getVoucherFromEvent(event);
      
      // 4. Check who was the authorized XLP
      const metadata = await this.getAtomicSwapMetadata(
        originChainId,
        requestId
      );
      const authorizedXlp = metadata.issuedBy;
      
      console.log(`✅ Authorized XLP was: ${authorizedXlp}`);
      console.log(`❌ Override by: ${xlpAddress}`);
      
      // 5. Dispute on both chains
      await this.disputeVoucherOverride(
        originChainId,
        destChainId,
        voucherRequest,
        overrideVoucher,
        xlpAddress
      );
    }
  }
  
  private async disputeVoucherOverride(
    originChainId: number,
    destChainId: number,
    voucherRequest: VoucherRequest,
    overrideVoucher: AtomicSwapVoucher,
    maliciousXlp: string
  ) {
    // 1. Accuse on destination
    const destPaymaster = this.destPaymasters.get(destChainId);
    const destTx = await destPaymaster.accuseFalseVoucherOverride(
      [voucherRequest],
      [overrideVoucher],
      this.beneficiaryAddress
    );
    await destTx.wait();
    
    console.log(`✅ Accusation submitted on dest chain`);
    
    // 2. Dispute on origin
    const originPaymaster = this.originPaymasters.get(originChainId);
    const disputeVouchers = [{
      voucherRequest: voucherRequest,
      voucher: overrideVoucher
    }];
    
    // Calculate bond
    const bondAmount = await this.calculateBond(voucherRequest);
    
    const originTx = await originPaymaster.disputeVoucherOverride(
      disputeVouchers,
      maliciousXlp,
      this.beneficiaryAddress,
      { value: bondAmount }
    );
    await originTx.wait();
    
    console.log(`✅ Dispute submitted on origin chain`);
    console.log(`⏳ Waiting for L1 resolution...`);
  }
}
```

---

## Event Monitoring

### Comprehensive Event Monitoring System

```typescript
class EventMonitoringService {
  private eventHandlers: Map<string, EventHandler[]> = new Map();
  
  /**
   * Setup all event listeners
   */
  async initialize() {
    // Monitor all origin chains
    for (const [chainId, paymaster] of this.originPaymasters) {
      this.monitorOriginChain(chainId, paymaster);
    }
    
    // Monitor all destination chains
    for (const [chainId, paymaster] of this.destPaymasters) {
      this.monitorDestinationChain(chainId, paymaster);
    }
    
    // Monitor L1
    this.monitorL1();
  }
  
  private monitorOriginChain(chainId: number, paymaster: Contract) {
    // VoucherRequestCreated
    paymaster.on(
      paymaster.filters.VoucherRequestCreated(),
      this.createHandler('VoucherRequestCreated', chainId)
    );
    
    // VoucherIssued
    paymaster.on(
      paymaster.filters.VoucherIssued(),
      this.createHandler('VoucherIssued', chainId)
    );
    
    // VoucherRedeemed
    paymaster.on(
      paymaster.filters.VoucherRedeemed(),
      this.createHandler('VoucherRedeemed', chainId)
    );
    
    // DisputeInitiated
    paymaster.on(
      paymaster.filters.DisputeInitiated(),
      this.createHandler('DisputeInitiated', chainId)
    );
    
    // XlpSlashedMessage
    paymaster.on(
      paymaster.filters.XlpSlashedMessage(),
      this.createHandler('XlpSlashedMessage', chainId)
    );
  }
  
  private monitorDestinationChain(chainId: number, paymaster: Contract) {
    // VoucherSpent
    paymaster.on(
      paymaster.filters.VoucherSpent(),
      this.createHandler('VoucherSpent', chainId)
    );
    
    // FalseVoucherOverrideAccused
    paymaster.on(
      paymaster.filters.FalseVoucherOverrideAccused(),
      this.createHandler('FalseVoucherOverrideAccused', chainId)
    );
    
    // ProvenVoucherSpent
    paymaster.on(
      paymaster.filters.ProvenVoucherSpent(),
      this.createHandler('ProvenVoucherSpent', chainId)
    );
  }
  
  private monitorL1() {
    const l1StakeManager = this.l1StakeManager;
    
    // XlpStakeAdded
    l1StakeManager.on(
      l1StakeManager.filters.XlpStakeAdded(),
      this.createHandler('XlpStakeAdded', 1)
    );
    
    // XlpSlashed
    l1StakeManager.on(
      l1StakeManager.filters.XlpSlashed(),
      this.createHandler('XlpSlashed', 1)
    );
    
    // DisputeResolved
    l1StakeManager.on(
      l1StakeManager.filters.DisputeResolved(),
      this.createHandler('DisputeResolved', 1)
    );
  }
  
  /**
   * Create event handler with error handling and logging
   */
  private createHandler(eventName: string, chainId: number) {
    return async (...args: any[]) => {
      const event = args[args.length - 1]; // Last arg is event
      
      try {
        console.log(`📡 [Chain ${chainId}] ${eventName}:`, {
          blockNumber: event.blockNumber,
          txHash: event.transactionHash
        });
        
        // Store in database
        await this.db.storeEvent({
          chainId,
          eventName,
          blockNumber: event.blockNumber,
          txHash: event.transactionHash,
          args: args.slice(0, -1), // All args except event
          timestamp: Date.now()
        });
        
        // Call registered handlers
        const handlers = this.eventHandlers.get(eventName) || [];
        for (const handler of handlers) {
          await handler(chainId, ...args);
        }
        
      } catch (error) {
        console.error(`❌ Error handling ${eventName}:`, error);
        await this.db.storeError({
          chainId,
          eventName,
          error: error.message,
          txHash: event.transactionHash
        });
      }
    };
  }
  
  /**
   * Register custom event handler
   */
  on(eventName: string, handler: EventHandler) {
    if (!this.eventHandlers.has(eventName)) {
      this.eventHandlers.set(eventName, []);
    }
    this.eventHandlers.get(eventName).push(handler);
  }
}

// Usage example
const monitor = new EventMonitoringService();

monitor.on('VoucherRequestCreated', async (chainId, requestId, sender, request) => {
  console.log(`New request ${requestId} on chain ${chainId}`);
  // XLP service can decide to issue voucher
});

monitor.on('VoucherSpent', async (chainId, requestId, sender, xlp) => {
  console.log(`Voucher ${requestId} spent by ${xlp}`);
  // XLP can mark for redemption
});

monitor.on('XlpSlashed', async (chainId, xlp, amount) => {
  console.log(`XLP ${xlp} slashed: ${amount}`);
  // Alert system, update XLP reputation
});

await monitor.initialize();
```

---

## Testing Strategies

### Integration Test Example

```typescript
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

describe('Cross-Chain Transfer Integration', () => {
  async function setupFixture() {
    // Deploy contracts on multiple chains (use hardhat parallel networks)
    const [user, xlp, challenger] = await ethers.getSigners();
    
    // L1
    const l1StakeManager = await deployL1StakeManager();
    
    // L2 Origin (Arbitrum fork)
    const originPaymaster = await deployPaymaster(ARBITRUM_CHAIN_ID);
    
    // L2 Dest (Optimism fork)
    const destPaymaster = await deployPaymaster(OPTIMISM_CHAIN_ID);
    
    // Setup bridges
    await setupMockBridges(l1StakeManager, originPaymaster, destPaymaster);
    
    // XLP stakes on L1
    await l1StakeManager.connect(xlp).addChainsInfo(
      [ARBITRUM_CHAIN_ID, OPTIMISM_CHAIN_ID],
      [chainInfoArbitrum, chainInfoOptimism],
      { value: ethers.utils.parseEther('100') }
    );
    
    // XLP registers and deposits liquidity
    await originPaymaster.connect(xlp).registerXlp(xlp.address);
    await destPaymaster.connect(xlp).registerXlp(xlp.address);
    await destPaymaster.connect(xlp).depositLiquidity([
      { token: USDC_ADDRESS, amount: ethers.utils.parseUnits('10000', 6) }
    ]);
    
    return { user, xlp, challenger, l1StakeManager, originPaymaster, destPaymaster };
  }
  
  it('Should complete cross-chain transfer successfully', async () => {
    const { user, xlp, originPaymaster, destPaymaster } = await loadFixture(setupFixture);
    
    // 1. User creates voucher request
    const voucherRequest = createVoucherRequest(
      user.address,
      USDC_ADDRESS,
      ethers.utils.parseUnits('100', 6),
      [xlp.address]
    );
    
    // 2. User locks funds
    await originPaymaster.connect(user).lockUserDeposit(voucherRequest);
    const requestId = computeRequestId(voucherRequest);
    
    // 3. XLP issues voucher
    const voucher = await createAndSignVoucher(xlp, voucherRequest);
    await originPaymaster.connect(xlp).issueVouchers([{
      voucher,
      voucherRequest
    }]);
    
    // 4. User withdraws on destination
    const userBalanceBefore = await getUSDCBalance(user.address);
    
    await destPaymaster.connect(user).withdrawFromVoucher(
      voucherRequest,
      voucher
    );
    
    const userBalanceAfter = await getUSDCBalance(user.address);
    
    // Verify user received funds
    expect(userBalanceAfter.sub(userBalanceBefore)).to.equal(
      ethers.utils.parseUnits('100', 6)
    );
    
    // 5. XLP redeems after delay
    await time.increase(VOUCHER_UNLOCK_DELAY);
    
    const xlpBalanceBefore = await getUSDCBalance(xlp.address);
    await originPaymaster.connect(xlp).redeemFulfilledVouchers([requestId]);
    const xlpBalanceAfter = await getUSDCBalance(xlp.address);
    
    // XLP gets original deposit + fee
    expect(xlpBalanceAfter.gt(xlpBalanceBefore)).to.be.true;
  });
  
  it('Should slash insolvent XLP', async () => {
    const { user, xlp, challenger, l1StakeManager, originPaymaster, destPaymaster } 
      = await loadFixture(setupFixture);
    
    // ... setup insolvency scenario ...
    
    // Challenger submits dispute
    await disputeInsolventXlp(challenger, voucherRequest, voucher);
    
    // Bridge messages to L1
    await bridgeDisputeToL1();
    
    // Verify stake was slashed
    const xlpStake = await l1StakeManager.getStake(xlp.address, ARBITRUM_CHAIN_ID);
    expect(xlpStake).to.be.lt(INITIAL_STAKE);
    
    // Verify challenger received reward
    // Verify user was compensated
  });
});
```

---

## Summary

This guide provides practical implementations for:

1. **XLP Services**: Stake management, voucher issuance, fee calculation, redemption
2. **User Wallets**: Cross-chain UserOp creation, voucher handling, ERC-4337 integration
3. **Challengers**: Dispute detection, evidence collection, bond calculation
4. **Event Monitoring**: Comprehensive event tracking across all chains
5. **Testing**: Integration test patterns for multi-chain scenarios

**Key Takeaways:**
- XLPs compete via reverse dutch auctions
- Vouchers are EIP-712 signed commitments
- Disputes require coordination between origin, destination, and L1
- Event-driven architecture is essential for off-chain services
- Robust error handling and monitoring are critical for production

Use these examples as templates for building production-ready EIL integrations!
