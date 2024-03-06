// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../libraries/TradingTypes.sol';
import '../libraries/Position.sol';

interface IExecution {

    event ExecuteIncreaseOrder(
        address account,
        uint256 orderId,
        uint256 pairIndex,
        TradingTypes.TradeType tradeType,
        bool isLong,
        int256 collateral,
        uint256 orderSize,
        uint256 orderPrice,
        uint256 executionSize,
        uint256 executionPrice,
        uint256 executedSize,
        uint256 tradingFee,
        int256 fundingFee,
        TradingTypes.InnerPaymentType paymentType,
        uint256 networkFeeAmount
    );

    event ExecuteDecreaseOrder(
        address account,
        uint256 orderId,
        uint256 pairIndex,
        TradingTypes.TradeType tradeType,
        bool isLong,
        int256 collateral,
        uint256 orderSize,
        uint256 orderPrice,
        uint256 executionSize,
        uint256 executionPrice,
        uint256 executedSize,
        bool needADL,
        int256 pnl,
        uint256 tradingFee,
        int256 fundingFee,
        TradingTypes.InnerPaymentType paymentType,
        uint256 networkFeeAmount
    );

    event ExecuteAdlOrder(
        uint256[] adlOrderIds,
        bytes32[] adlPositionKeys,
        uint256[] orders
    );

    event ExecuteOrderError(uint256 orderId, string errorMessage);
    event ExecutePositionError(bytes32 positionKey, string errorMessage);

    event InvalidOrder(address sender, uint256 orderId, string message);
    event ZeroPosition(address sender, address account, uint256 pairIndex, bool isLong, string message);

    struct ExecutePosition {
        bytes32 positionKey;
        uint256 sizeAmount;
        uint8 tier;
        uint256 referralsRatio;
        uint256 referralUserRatio;
        address referralOwner;
    }

    struct LiquidatePosition {
        address token;
        bytes updateData;
        uint256 updateFee;
        uint64 backtrackRound;
        bytes32 positionKey;
        uint256 sizeAmount;
        uint8 tier;
        uint256 referralsRatio;
        uint256 referralUserRatio;
        address referralOwner;
    }

    struct PositionOrder {
        address account;
        uint256 pairIndex;
        bool isLong;
    }
}
