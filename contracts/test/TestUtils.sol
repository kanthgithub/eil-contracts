// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../L1AtomicSwapStakeManager.sol";

contract TestUtils {
    function deployStakeManager(uint256 unstakeDelay, uint256 maxChainsPerXlp, address owner) external returns (L1AtomicSwapStakeManager) {
        return new L1AtomicSwapStakeManager(
            L1AtomicSwapStakeManager.Config({
                claimDelay: 8 days,
                destBeforeOriginMinGap: 10 seconds,
                minStakePerChain: 1 ether,
                unstakeDelay: unstakeDelay,
                maxChainsPerXlp: maxChainsPerXlp,
                l2SlashedGasLimit: 1_000_001,
                l2StakedGasLimit: 1_000_000,
                owner: owner
            })
        );
    }
}
