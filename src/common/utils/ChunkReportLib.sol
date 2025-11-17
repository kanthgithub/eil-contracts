// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../Errors.sol";
import "../../types/Enums.sol";

library ChunkReportLib {
    struct ChunkContext {
        uint256 origChainId;
        uint256 destChainId;
        bytes32 reportId;
    }

    function buildContext(
        address xlpToSlash,
        address reporter,
        address payable l1Beneficiary,
        DisputeType disputeType,
        uint256 origChainId,
        uint256 destChainId,
        uint256 numberOfChunks,
        uint256 nonce
    ) internal pure returns (ChunkContext memory context) {
        context.origChainId = origChainId;
        context.destChainId = destChainId;
        context.reportId = computeReportId(
            xlpToSlash,
            reporter,
            l1Beneficiary,
            disputeType,
            origChainId,
            destChainId,
            numberOfChunks,
            nonce
        );
    }

    struct ChunkReportState {
        uint256 expectedChunks;
        uint256 nextChunkIndex;
        uint256 totalVoucherCount;
        bytes32 aggregatedRequestIdsHash;
        bytes32 committedRequestIdsHash;
        uint256 committedVoucherCount;
        uint256 firstChunkSubmittedAt;
        address reporter;
        address xlpToSlash;
        address payable l1Beneficiary;
        uint256 origChainId;
        uint256 destChainId;
        uint256 nonce;
    }

    function computeReportId(
        address xlpToSlash,
        address reporter,
        address l1Beneficiary,
        DisputeType disputeType,
        uint256 origChainId,
        uint256 destChainId,
        uint256 numberOfChunks,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                xlpToSlash,
                reporter,
                l1Beneficiary,
                disputeType,
                origChainId,
                destChainId,
                numberOfChunks,
                nonce
            )
        );
    }

    function validateChunkInputs(
        uint256 numberOfChunks,
        uint256 chunkIndex,
        uint256 itemCount,
        string memory emptyErrorLabel,
        uint256 lengthValue
    ) internal pure {
        require(numberOfChunks > 0, InvalidChunkCount(1, numberOfChunks));
        require(chunkIndex < numberOfChunks, InvalidChunkIndex(numberOfChunks - 1, chunkIndex));
        require(itemCount > 0, InvalidLength(emptyErrorLabel, 0, lengthValue));
    }

    function initializeFirstChunk(
        ChunkReportState storage state,
        mapping(address => uint256) storage reporterNonces,
        address reporter,
        address xlpToSlash,
        address payable l1Beneficiary,
        uint256 origChainId,
        uint256 destChainId,
        uint256 numberOfChunks,
        uint256 nonce,
        bytes32 committedRequestIdsHash,
        uint256 committedVoucherCount
    ) internal returns (uint256 chunkTimestamp) {
        uint256 nextNonce = reporterNonces[reporter] + 1;
        require(nonce == nextNonce, InvalidReportNonce(nextNonce, nonce));
        require(state.expectedChunks == 0, InvalidChunkCount(0, state.expectedChunks));
        reporterNonces[reporter] = nextNonce;

        state.expectedChunks = numberOfChunks;
        state.nextChunkIndex = 0;
        state.totalVoucherCount = 0;
        state.aggregatedRequestIdsHash = bytes32(0);
        state.committedRequestIdsHash = committedRequestIdsHash;
        state.committedVoucherCount = committedVoucherCount;
        chunkTimestamp = block.timestamp;
        state.firstChunkSubmittedAt = chunkTimestamp;
        state.reporter = reporter;
        state.xlpToSlash = xlpToSlash;
        state.l1Beneficiary = l1Beneficiary;
        state.origChainId = origChainId;
        state.destChainId = destChainId;
        state.nonce = nonce;
    }

    function requireExistingReport(ChunkReportState storage state) internal view {
        require(state.expectedChunks > 1, InvalidChunkCount(2, state.expectedChunks));
    }

    function requireExpectedChunkIndex(ChunkReportState storage state, uint256 chunkIndex) internal view {
        require(state.nextChunkIndex == chunkIndex, InvalidChunkIndex(state.nextChunkIndex, chunkIndex));
    }

    function foldChunk(
        ChunkReportState storage state,
        bytes32 chunkHash,
        uint256 chunkSize,
        uint256 chunkIndex
    ) internal {
        bytes32 aggregatedHash = state.aggregatedRequestIdsHash;
        if (aggregatedHash == bytes32(0)) {
            state.aggregatedRequestIdsHash = chunkHash;
        } else {
            state.aggregatedRequestIdsHash = keccak256(abi.encode(aggregatedHash, chunkHash));
        }
        state.totalVoucherCount += chunkSize;
        state.nextChunkIndex = chunkIndex + 1;
    }

    function finalizeCommitment(ChunkReportState storage state) internal view returns (bytes32 aggregatedHash) {
        aggregatedHash = state.aggregatedRequestIdsHash;
        require(aggregatedHash != bytes32(0), InvalidLength("empty aggregated hash", 1, 0));
        require(
            aggregatedHash == state.committedRequestIdsHash,
            DisputeCommitmentMismatch(state.committedRequestIdsHash, aggregatedHash)
        );
        require(
            state.totalVoucherCount == state.committedVoucherCount,
            InvalidLength("Committed vouchers", state.committedVoucherCount, state.totalVoucherCount)
        );
    }
}
