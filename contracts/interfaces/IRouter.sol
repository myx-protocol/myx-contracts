// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/TradingTypes.sol";

interface IRouter {
    struct AddOrderTpSlRequest {
        uint256 orderId;
        TradingTypes.TradeType tradeType;
        bool isIncrease;
        uint256 tpPrice; // Stop profit price 1e30
        uint128 tp; // The number of profit stops
        uint256 slPrice; // Stop price 1e30
        uint128 sl; // Stop loss quantity
        TradingTypes.NetworkFeePaymentType paymentType;
        uint256 tpNetworkFeeAmount;
        uint256 slNetworkFeeAmount;
    }

    struct CancelOrderRequest {
        uint256 orderId;
        TradingTypes.TradeType tradeType;
        bool isIncrease;
    }

    struct OperationStatus {
        bool increasePositionDisabled;
        bool decreasePositionDisabled;
        bool orderDisabled;
        bool addLiquidityDisabled;
        bool removeLiquidityDisabled;
    }

    event UpdateTradingRouter(address oldAddress, address newAddress);

    event UpdateIncreasePositionStatus(address sender, uint256 pairIndex, bool enabled);
    event UpdateDecreasePositionStatus(address sender, uint256 pairIndex, bool enabled);
    event UpdateOrderStatus(address sender, uint256 pairIndex, bool enabled);
    event UpdateAddLiquidityStatus(address sender, uint256 pairIndex, bool enabled);
    event UpdateRemoveLiquidityStatus(address sender, uint256 pairIndex, bool enabled);

    function getOperationStatus(uint256 pairIndex) external view returns (OperationStatus memory);
}
