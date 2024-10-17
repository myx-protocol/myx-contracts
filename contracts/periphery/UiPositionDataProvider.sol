// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../interfaces/IUiPositionDataProvider.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPositionManager.sol";
import "../interfaces/IPoolView.sol";
import "../helpers/TradingHelper.sol";

contract UiPositionDataProvider is IUiPositionDataProvider {

    IAddressesProvider public immutable ADDRESS_PROVIDER;

    constructor(IAddressesProvider addressProvider){
        ADDRESS_PROVIDER = addressProvider;
    }

    function getPositionsData(
        IPool pool,
        IPoolView poolView,
        IPositionManager positionManager,
        uint256[] memory pairIndexes,
        uint256[] memory prices
    ) public view returns (PositionData[] memory) {
        require(pairIndexes.length == prices.length, "nl");

        PositionData[] memory positionsData = new PositionData[](pairIndexes.length);
        for (uint256 i = 0; i < pairIndexes.length; i++) {
            uint256 pairIndex = pairIndexes[i];
            uint256 price = prices[i];
            PositionData memory positionData = positionsData[i];

            IPool.Pair memory pair = pool.getPair(pairIndex);
            positionData.pairIndex = pair.pairIndex;
            positionData.exposedPositions = positionManager.getExposedPositions(pairIndex);
            positionData.longTracker = positionManager.longTracker(pairIndex);
            positionData.shortTracker = positionManager.shortTracker(pairIndex);

            IPool.Vault memory vault = pool.getVault(pairIndex);
            positionData.indexTotalAmount = vault.indexTotalAmount;
            positionData.indexReservedAmount = vault.indexReservedAmount;
            positionData.stableTotalAmount = vault.stableTotalAmount;
            positionData.stableReservedAmount = vault.stableReservedAmount;
            positionData.poolAvgPrice = vault.averagePrice;

            positionData.currentFundingRate = positionManager.getCurrentFundingRate(pairIndex);
            positionData.nextFundingRate = positionManager.getNextFundingRate(pairIndex, price);
            positionData.nextFundingRateUpdateTime = positionManager.getNextFundingRateUpdateTime(pairIndex);

            positionData.lpPrice = poolView.lpFairPrice(pairIndex, price);
            positionData.lpTotalSupply = IERC20(pair.pairToken).totalSupply();

            int256 exposedPositions = positionManager.getExposedPositions(pairIndex);
            positionData.longLiquidity = TradingHelper.maxAvailableLiquidity(vault, pair, exposedPositions, true, price);
            positionData.shortLiquidity = TradingHelper.maxAvailableLiquidity(vault, pair, exposedPositions, false, price);
        }

        return positionsData;
    }

    function getUserPositionData(
        IPositionManager positionManager,
        bytes32[] memory positionKeys
    ) external view returns (UserPositionData[] memory) {
        UserPositionData[] memory positions = new UserPositionData[](positionKeys.length);
        for (uint256 i = 0; i < positionKeys.length; i++) {
            UserPositionData memory position = positions[i];
            Position.Info memory info = positionManager.getPositionByKey(positionKeys[i]);

            position.account = info.account;
            position.pairIndex = info.pairIndex;
            position.isLong = info.isLong;
            position.collateral = info.collateral;
            position.positionAmount = info.positionAmount;
            position.averagePrice = info.averagePrice;
            position.fundingFeeTracker = info.fundingFeeTracker;
        }
        return positions;
    }

    struct PairPrice {
        uint256 pairIndex;
        uint256 price;
    }

    function getUserPositionDataV2(
        IPositionManager positionManager,
        address account,
        PairPrice[] memory pairs
    ) external view returns (UserPositionDataV2[] memory) {
        UserPositionDataV2[] memory positions = new UserPositionDataV2[](pairs.length * 2);
        for (uint256 i = 0; i < pairs.length; i++) {
            uint256 price = pairs[i].price;

            bytes32 positionKey1 = PositionKey.getPositionKey(account, pairs[i].pairIndex, true);
            Position.Info memory info1 = positionManager.getPositionByKey(positionKey1);
            UserPositionDataV2 memory position1 = positions[i * 2];
            position1.key = positionKey1;
            position1.account = info1.account;
            position1.pairIndex = info1.pairIndex;
            position1.isLong = info1.isLong;
            position1.collateral = info1.collateral;
            position1.positionAmount = info1.positionAmount;
            position1.averagePrice = info1.averagePrice;
            position1.fundingFeeTracker = info1.fundingFeeTracker;
            position1.positionCloseTradingFee = positionManager.getTradingFee(pairs[i].pairIndex, true, false, info1.positionAmount, price);
            position1.positionFundingFee = positionManager.getFundingFee(account, pairs[i].pairIndex, true);

            bytes32 positionKey2 = PositionKey.getPositionKey(account, pairs[i].pairIndex, false);
            Position.Info memory info2 = positionManager.getPositionByKey(positionKey2);
            UserPositionDataV2 memory position2 = positions[i * 2 + 1];
            position2.key = positionKey2;
            position2.account = info2.account;
            position2.pairIndex = info2.pairIndex;
            position2.isLong = info2.isLong;
            position2.collateral = info2.collateral;
            position2.positionAmount = info2.positionAmount;
            position2.averagePrice = info2.averagePrice;
            position2.fundingFeeTracker = info2.fundingFeeTracker;
            position2.positionCloseTradingFee = positionManager.getTradingFee(pairs[i].pairIndex, false, false, info2.positionAmount, price);
            position2.positionFundingFee = positionManager.getFundingFee(account, pairs[i].pairIndex, false);
        }
        return positions;
    }
}
