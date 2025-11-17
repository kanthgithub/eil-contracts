// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../types/Constants.sol";
import "../Errors.sol";
import "../../types/Asset.sol";

library AssetUtils {
    using SafeERC20 for IERC20;

    function withAmount(Asset memory baseAsset, uint256 newAmount) internal pure returns (Asset memory) {
        return Asset({
            erc20Token: baseAsset.erc20Token,
            amount: newAmount
        });
    }

    function transfer(Asset memory asset, address payable to) internal {
        if (asset.amount == 0){
            return;
        }
        if (asset.erc20Token == NATIVE_ETH) {
            _transferNative(asset, to);
        } else {
            _transferERC20(asset, to);
        }
    }

    function secure(Asset memory asset, address sender) internal {
        if (asset.erc20Token == NATIVE_ETH) {
            _secureNative(asset);
        } else {
            _secureERC20(asset, sender);
        }
    }

    function _secureERC20(Asset memory asset, address sender) private {
        IERC20(asset.erc20Token).safeTransferFrom(sender, address(this), asset.amount);
    }

    function _secureNative(Asset memory asset) private {
        require(asset.amount == msg.value, AmountMismatch("receive ether", asset.amount, msg.value));
    }

    function _transferERC20(Asset memory asset, address payable to) private {
        IERC20(asset.erc20Token).safeTransfer(to, asset.amount);
    }

    function _transferNative(Asset memory asset, address payable to) private {
        (bool success, bytes memory revertReason) = to.call{value: asset.amount}("");
        require(success, ExternalCallReverted("withdrawal", to, revertReason));
    }
}
