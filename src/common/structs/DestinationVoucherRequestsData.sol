// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../types/Asset.sol";
import "../../types/DestinationSwapComponent.sol";
import "../../types/SourceSwapComponent.sol";

struct DestinationVoucherRequestsData {
    Asset[][] vouchersAssetsMinimums;
    address ephemeralSigner;
}
