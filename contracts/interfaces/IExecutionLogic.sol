// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/TradingTypes.sol";
import "../libraries/Position.sol";
import "./IExecution.sol";

interface IExecutionLogic is IExecution {
    event UpdateMaxTimeDelay(uint256 oldDelay, uint256 newDelay);

    event UpdateExecutorAddress(address sender, address oldAddress, address newAddress);

    struct ExecuteOrder {
        uint256 orderId;
        TradingTypes.TradeType tradeType;
        bool isIncrease;
        uint8 tier;
        uint256 referralsRatio;
        uint256 referralUserRatio;
        address referralOwner;
    }

    struct ExecutePositionInfo {
        Position.Info position;
        uint256 executionSize;
        uint8 tier;
        uint256 referralsRatio;
        uint256 referralUserRatio;
        address referralOwner;
    }

    function maxTimeDelay() external view returns (uint256);

    function updateExecutor(address _executor) external;

    function updateMaxTimeDelay(uint256 newMaxTimeDelay) external;

    function executeIncreaseOrders(
        address keeper,
        ExecuteOrder[] memory orders,
        TradingTypes.TradeType tradeType
    ) external;

    function executeIncreaseOrder(
        address keeper,
        uint256 _orderId,
        TradingTypes.TradeType _tradeType,
        uint8 tier,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner
    ) external;

    function executeDecreaseOrders(
        address keeper,
        ExecuteOrder[] memory orders,
        TradingTypes.TradeType tradeType
    ) external;

    function executeDecreaseOrder(
        address keeper,
        uint256 _orderId,
        TradingTypes.TradeType _tradeType,
        uint8 tier,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner,
        bool isSystem,
        uint256 executionSize,
        bool onlyOnce
    ) external;

    function executeADLAndDecreaseOrders(
        address keeper,
        uint256 pairIndex,
        ExecutePosition[] memory executePositions,
        IExecutionLogic.ExecuteOrder[] memory executeOrders
    ) external;
}
