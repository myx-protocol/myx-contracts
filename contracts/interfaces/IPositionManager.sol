// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import '../libraries/Position.sol';
import "./IFeeCollector.sol";

enum PositionStatus {
    Balance,
    NetLong,
    NetShort
}

interface IPositionManager {
    event UpdateFundingInterval(uint256 oldInterval, uint256 newInterval);

    event UpdatePosition(
        address account,
        bytes32 positionKey,
        uint256 pairIndex,
        uint256 orderId,
        bool isLong,
        uint256 beforCollateral,
        uint256 afterCollateral,
        uint256 price,
        uint256 beforPositionAmount,
        uint256 afterPositionAmount,
        uint256 averagePrice,
        int256 fundFeeTracker,
        int256 pnl
    );

    event UpdatedExecutionLogic(address sender, address oldAddress, address newAddress);

    event UpdatedLiquidationLogic(address sender, address oldAddress, address newAddress);

    event UpdateRouterAddress(address sender, address oldAddress, address newAddress);

    event UpdateFundingRate(uint256 pairIndex, uint price, int256 fundingRate, uint256 lastFundingTime);

    event TakeFundingFeeAddTraderFee(
        address account,
        uint256 pairIndex,
        uint256 orderId,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        uint256 lpTradingFee,
        uint256 vipDiscountAmount
    );

    event AdjustCollateral(
        address account,
        uint256 pairIndex,
        bool isLong,
        bytes32 positionKey,
        uint256 collateralBefore,
        uint256 collateralAfter
    );

    function getExposedPositions(uint256 pairIndex) external view returns (int256);

    function longTracker(uint256 pairIndex) external view returns (uint256);

    function shortTracker(uint256 pairIndex) external view returns (uint256);

    function getTradingFee(
        uint256 _pairIndex,
        bool _isLong,
        uint256 _sizeAmount,
        uint256 price
    ) external view returns (uint256 tradingFee);

    function getFundingFee(
        address _account,
        uint256 _pairIndex,
        bool _isLong
    ) external view returns (int256 fundingFee);

    function getCurrentFundingRate(uint256 _pairIndex) external view returns (int256);

    function getNextFundingRate(uint256 _pairIndex, uint256 price) external view returns (int256);

    function getNextFundingRateUpdateTime(uint256 _pairIndex) external view returns (uint256);

    function needADL(
        uint256 pairIndex,
        bool isLong,
        uint256 executionSize,
        uint256 executionPrice
    ) external view returns (bool needADL, uint256 needADLAmount);

    function needLiquidation(
        bytes32 positionKey,
        uint256 price
    ) external view returns (bool);

    function getPosition(
        address _account,
        uint256 _pairIndex,
        bool _isLong
    ) external view returns (Position.Info memory);

    function getPositionByKey(bytes32 key) external view returns (Position.Info memory);

    function getPositionKey(address _account, uint256 _pairIndex, bool _isLong) external pure returns (bytes32);

    function increasePosition(
        uint256 _pairIndex,
        uint256 orderId,
        address _account,
        address _keeper,
        uint256 _sizeAmount,
        bool _isLong,
        int256 _collateral,
        IFeeCollector.TradingFeeTier memory tradingFeeTier,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner,
        uint256 _price
    ) external returns (uint256 tradingFee, int256 fundingFee);

    function decreasePosition(
        uint256 _pairIndex,
        uint256 orderId,
        address _account,
        address _keeper,
        uint256 _sizeAmount,
        bool _isLong,
        int256 _collateral,
        IFeeCollector.TradingFeeTier memory tradingFeeTier,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner,
        uint256 _price,
        bool useRiskReserve
    ) external returns (uint256 tradingFee, int256 fundingFee, int256 pnl);

    function adjustCollateral(uint256 pairIndex, address account, bool isLong, int256 collateral) external;

    function updateFundingRate(uint256 _pairIndex) external;

    function lpProfit(uint pairIndex, address token, uint256 price) external view returns (int256 profit);
}
