// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../libraries/PrecisionUtils.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IOraclePriceFeed.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IBacktracker.sol";
import "../helpers/TokenHelper.sol";
import "../libraries/Int256Utils.sol";

library TradingHelper {
    using PrecisionUtils for uint256;
    using Int256Utils for int256;

    function getValidPrice(
        IAddressesProvider addressesProvider,
        address token,
        IPool.TradingConfig memory tradingConfig
    ) internal view returns (uint256) {
        bool backtracking = IBacktracker(addressesProvider.backtracker()).backtracking();
        if (backtracking) {
            uint64 backtrackRound = IBacktracker(addressesProvider.backtracker()).backtrackRound();
            return IOraclePriceFeed(addressesProvider.priceOracle()).getHistoricalPrice(backtrackRound, token);
        }
        uint256 oraclePrice = IPriceFeed(addressesProvider.priceOracle()).getPriceSafely(token);
        uint256 indexPrice = IPriceFeed(addressesProvider.indexPriceOracle()).getPrice(token);

        uint256 diffP = oraclePrice > indexPrice
            ? oraclePrice - indexPrice
            : indexPrice - oraclePrice;
        diffP = diffP.calculatePercentage(oraclePrice);

        require(diffP <= tradingConfig.maxPriceDeviationP, "exceed max price deviation");
        return oraclePrice;
    }

    function exposureAmountChecker(
        IPool.Vault memory lpVault,
        IPool.Pair memory pair,
        int256 exposedPositions,
        bool isLong,
        uint256 orderSize,
        uint256 executionPrice
    ) internal view returns (uint256 executionSize) {
        executionSize = orderSize;

        uint256 available = maxAvailableLiquidity(lpVault, pair, exposedPositions, isLong, executionPrice);
        if (executionSize > available) {
            executionSize = available;
        }
        return executionSize;
    }

    function maxAvailableLiquidity(
        IPool.Vault memory lpVault,
        IPool.Pair memory pair,
        int256 exposedPositions,
        bool isLong,
        uint256 executionPrice
    ) internal view returns (uint256 amount) {
        if (exposedPositions >= 0) {
            if (isLong) {
                amount = lpVault.indexTotalAmount >= lpVault.indexReservedAmount ?
                    lpVault.indexTotalAmount - lpVault.indexReservedAmount : 0;
            } else {
                int256 availableStable = int256(lpVault.stableTotalAmount) - int256(lpVault.stableReservedAmount);
                int256 stableToIndexAmount = TokenHelper.convertStableAmountToIndex(
                    pair,
                    availableStable
                );
                if (stableToIndexAmount < 0) {
                    if (uint256(exposedPositions) <= stableToIndexAmount.abs().divPrice(executionPrice)) {
                        amount = 0;
                    } else {
                        amount = uint256(exposedPositions) - stableToIndexAmount.abs().divPrice(executionPrice);
                    }
                } else {
                    amount = uint256(exposedPositions) + stableToIndexAmount.abs().divPrice(executionPrice);
                }
            }
        } else {
            if (isLong) {
                int256 availableIndex = int256(lpVault.indexTotalAmount) - int256(lpVault.indexReservedAmount);
                if (availableIndex > 0) {
                    amount = uint256(-exposedPositions) + availableIndex.abs();
                } else {
                    amount = uint256(-exposedPositions) >= availableIndex.abs() ?
                        uint256(-exposedPositions) - availableIndex.abs() : 0;
                }
            } else {
                int256 availableStable = int256(lpVault.stableTotalAmount) - int256(lpVault.stableReservedAmount);
                int256 stableToIndexAmount = TokenHelper.convertStableAmountToIndex(
                    pair,
                    availableStable
                );
                if (stableToIndexAmount < 0) {
                    amount = 0;
                } else {
                    amount = stableToIndexAmount.abs().divPrice(executionPrice);
                }
            }
        }
        return amount;
    }
}
