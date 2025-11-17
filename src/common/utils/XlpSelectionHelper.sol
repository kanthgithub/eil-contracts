// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../types/Asset.sol";
import "../../ICrossChainPaymaster.sol";
import "../../types/Constants.sol";

struct XlpEntryBalanceInfo {
    /** @notice xlp entry */
    XlpEntry xlpEntry;
    /** @notice  for each asset, the deposit in the paymaster */
    uint256[] deposits;
    /** @notice for each asset, the actual token balance */
    uint256[] balances;
}

contract XlpSelectionHelper {
    /**
     * Returns XLPs that control sufficient amounts of the given assets.
     * @param paymaster the ICrossChainPaymaster contract to query for registered XLPs.
     * @param offset The starting position in the Paymaster's list of registered XLPs.
     * @param length The maximum number of XLPs in the list to check.
     * @param assets a list of assets and amounts to use as a filter for registered XLPs.
     * @param includeBalance Set this value to true to consider assets held directly by the EOA as available.
     *                       Note that the XLP still needs to deposit the assets before issuing a voucher using them.
     * @return out a list of solvent XLPs, and their balances
     */
    function getSolventXlps(
        ICrossChainPaymaster paymaster,
        uint256 offset,
        uint256 length,
        Asset[] memory assets,
        bool includeBalance
    )
    public
    view
    returns (
        XlpEntryBalanceInfo[] memory
    ) {
        XlpEntry[] memory xlps = paymaster.getXlps(offset, length);
        XlpEntryBalanceInfo[] memory solventXlps = new XlpEntryBalanceInfo[](xlps.length);

        uint256 index = 0;
        for (uint256 i = 0; i < xlps.length; i++) {
            XlpEntry memory xlp = xlps[i];
            (XlpEntryBalanceInfo memory info, bool isSolvent) =
                            getXlpInfo(paymaster, xlp, assets, includeBalance, true);
            if (!isSolvent) {
                continue;
            }
            solventXlps[index++] = info;
        }

        // set output array size to actual number of solvent xlps
        // solhint-disable-next-line no-inline-assembly
        assembly {mstore(solventXlps, index)}
        return solventXlps;
    }

    /**
     * @notice Returns deposit and balance information for a given XLP across a list of assets.
     * @dev Iterates through the provided assets and checks the deposit and balance for each.
     *      If, for any asset, the sum of deposit and balance is less than the required amount,
     *      the XLP is marked as insolvent by setting `l2XlpAddress` to address(0).
     * @param paymaster The paymaster contract used to query token deposits.
     * @param xlp The XLP entry containing L1 and L2 XLP addresses.
     * @param includeBalance Set this value to true to consider assets held directly by the EOA as available.
     *                       Note that the XLP still needs to deposit the assets before issuing a voucher using them.
     * @param filterInsolvent Set this value to true to stop collecting balances if the XLP is insolvent to save gas.
     * @param assets The list of assets to check balances and deposits for.
     * @return xlpInfo A struct containing the deposit and balance information for each asset,
     *         as well as the updated L1 and L2 XLP addresses. If insolvent, `l2XlpAddress` is address(0).
     * @return isSolvent A flag indicating whether the XLP controls the required amount of assets.
     */
    function getXlpInfo(
        ICrossChainPaymaster paymaster,
        XlpEntry memory xlp,
        Asset[] memory assets,
        bool includeBalance,
        bool filterInsolvent
    )
    public
    view
    returns (
        XlpEntryBalanceInfo memory xlpInfo, bool isSolvent
    ) {
        xlpInfo.xlpEntry = xlp;
        xlpInfo.deposits = new uint256[](assets.length);
        xlpInfo.balances = new uint256[](assets.length);
        address l2XlpAddress = xlp.l2XlpAddress;
        isSolvent = true;
        for (uint256 j = 0; j < assets.length; j++) {
            Asset memory asset = assets[j];
            uint256 deposit = paymaster.tokenBalanceOf(asset.erc20Token, l2XlpAddress);
            uint256 balance;
            if (includeBalance) {
                balance += assetBalance(asset, l2XlpAddress);
            }

            if (deposit + balance < asset.amount) {
                isSolvent = false;
                if (filterInsolvent) {
                    return (xlpInfo, isSolvent);
                }
            }
            xlpInfo.deposits[j] = deposit;
            xlpInfo.balances[j] = balance;
        }
        return (xlpInfo, isSolvent);
    }

    function assetBalance(Asset memory asset, address holder) internal view returns (uint256) {
        if (asset.erc20Token == NATIVE_ETH) {
            return holder.balance;
        } else {
            return IERC20(asset.erc20Token).balanceOf(holder);
        }
    }
}
