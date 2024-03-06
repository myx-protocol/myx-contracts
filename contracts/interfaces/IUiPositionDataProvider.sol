// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IUiPositionDataProvider {

    struct PositionData {
        uint256 pairIndex;
        int256 exposedPositions;
        uint256 longTracker;
        uint256 shortTracker;
        uint256 indexTotalAmount;
        uint256 indexReservedAmount;
        uint256 stableTotalAmount;
        uint256 stableReservedAmount;
        uint256 poolAvgPrice;
        int256 currentFundingRate;
        int256 nextFundingRate;
        uint256 nextFundingRateUpdateTime;
        uint256 lpPrice;
        uint256 lpTotalSupply;
        uint256 longLiquidity;
        uint256 shortLiquidity;
    }

}
