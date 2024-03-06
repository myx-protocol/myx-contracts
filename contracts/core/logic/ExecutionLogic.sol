// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../../libraries/Position.sol";
import "../../interfaces/IExecutionLogic.sol";
import "../../interfaces/IAddressesProvider.sol";
import "../../interfaces/IRoleManager.sol";
import "../../interfaces/IOrderManager.sol";
import "../../interfaces/IPositionManager.sol";
import "../../interfaces/IPool.sol";
import "../../helpers/ValidationHelper.sol";
import "../../helpers/TradingHelper.sol";
import "../../interfaces/IFeeCollector.sol";
import "../../interfaces/IExecutor.sol";

contract ExecutionLogic is IExecutionLogic {
    using PrecisionUtils for uint256;
    using Math for uint256;
    using Int256Utils for int256;
    using Int256Utils for uint256;
    using Position for Position.Info;

    uint256 public override maxTimeDelay;

    IAddressesProvider public immutable ADDRESS_PROVIDER;

    IPool public immutable pool;
    IOrderManager public immutable orderManager;
    IPositionManager public immutable positionManager;
    address public executor;

    IFeeCollector public immutable feeCollector;

    constructor(
        IAddressesProvider addressProvider,
        IPool _pool,
        IOrderManager _orderManager,
        IPositionManager _positionManager,
        IFeeCollector _feeCollector,
        uint256 _maxTimeDelay
    ) {
        ADDRESS_PROVIDER = addressProvider;
        pool = _pool;
        orderManager = _orderManager;
        positionManager = _positionManager;
        feeCollector = _feeCollector;
        maxTimeDelay = _maxTimeDelay;
    }

    modifier onlyPoolAdmin() {
        require(IRoleManager(ADDRESS_PROVIDER.roleManager()).isPoolAdmin(msg.sender), "opa");
        _;
    }

    modifier onlyExecutorOrSelf() {
        require(msg.sender == executor || msg.sender == address(this), "oe");
        _;
    }

    function updateExecutor(address _executor) external override onlyPoolAdmin {
        address oldAddress = executor;
        executor = _executor;
        emit UpdateExecutorAddress(msg.sender, oldAddress, _executor);
    }

    function updateMaxTimeDelay(uint256 newMaxTimeDelay) external override onlyPoolAdmin {
        uint256 oldDelay = maxTimeDelay;
        maxTimeDelay = newMaxTimeDelay;
        emit UpdateMaxTimeDelay(oldDelay, newMaxTimeDelay);
    }

    function executeIncreaseOrders(
        address keeper,
        ExecuteOrder[] memory orders,
        TradingTypes.TradeType tradeType
    ) external override onlyExecutorOrSelf {
        for (uint256 i = 0; i < orders.length; i++) {
            ExecuteOrder memory order = orders[i];

            try
                this.executeIncreaseOrder(
                    keeper,
                    order.orderId,
                    tradeType,
                    order.tier,
                    order.referralsRatio,
                    order.referralUserRatio,
                    order.referralOwner
                )
            {} catch Error(string memory reason) {
                emit ExecuteOrderError(order.orderId, reason);
                orderManager.cancelOrder(
                    order.orderId,
                    tradeType,
                    true,
                    reason
                );
            }
        }
    }

    function executeIncreaseOrder(
        address keeper,
        uint256 _orderId,
        TradingTypes.TradeType _tradeType,
        uint8 tier,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner
    ) external override onlyExecutorOrSelf {
        TradingTypes.OrderNetworkFee memory orderNetworkFee;
        TradingTypes.IncreasePositionOrder memory order;
        (order, orderNetworkFee) = orderManager.getIncreaseOrder(_orderId, _tradeType);
        if (order.account == address(0)) {
            emit InvalidOrder(keeper, _orderId, 'address 0');
            return;
        }

        // is expired
        if (order.tradeType == TradingTypes.TradeType.MARKET) {
            require(order.blockTime + maxTimeDelay >= block.timestamp, "order expired");
        }

        // check pair enable
        uint256 pairIndex = order.pairIndex;
        IPool.Pair memory pair = pool.getPair(pairIndex);
        if (!pair.enable) {
            orderManager.cancelOrder(order.orderId, order.tradeType, true, "!enable");
            return;
        }

        IPool.TradingConfig memory tradingConfig = pool.getTradingConfig(pairIndex);

        // validate can be triggered
        uint256 executionPrice = TradingHelper.getValidPrice(
            ADDRESS_PROVIDER,
            pair.indexToken,
            tradingConfig
        );
        bool isAbove = order.isLong &&
            (order.tradeType == TradingTypes.TradeType.MARKET ||
                order.tradeType == TradingTypes.TradeType.LIMIT);
        ValidationHelper.validatePriceTriggered(
            tradingConfig,
            order.tradeType,
            isAbove,
            executionPrice,
            order.openPrice,
            order.maxSlippage
        );

        bytes32 positionKey = positionManager.getPositionKey(order.account, order.pairIndex, order.isLong);
        // get position
        Position.Info memory position = positionManager.getPosition(order.account, order.pairIndex, order.isLong);
        require(
            position.positionAmount == 0 || !positionManager.needLiquidation(positionKey, executionPrice),
            "need liquidation"
        );

        // compare openPrice and oraclePrice
        if (order.tradeType == TradingTypes.TradeType.LIMIT) {
            if (order.isLong) {
                executionPrice = Math.min(order.openPrice, executionPrice);
            } else {
                executionPrice = Math.max(order.openPrice, executionPrice);
            }
        }

        IPool.Vault memory lpVault = pool.getVault(pairIndex);
        int256 exposureAmount = positionManager.getExposedPositions(pairIndex);

        uint256 orderSize = order.sizeAmount - order.executedSize;
        uint256 executionSize;
        if (orderSize > 0) {
            (executionSize) = TradingHelper.exposureAmountChecker(
                lpVault,
                pair,
                exposureAmount,
                order.isLong,
                orderSize,
                executionPrice
            );
            if (executionSize == 0) {
                orderManager.cancelOrder(order.orderId, order.tradeType, true, "nal");
                return;
            }
        }

        int256 collateral;
        if (order.collateral > 0) {
            collateral = order.executedSize == 0 || order.tradeType == TradingTypes.TradeType.MARKET
                ? order.collateral
                : int256(0);
        } else {
            collateral = order.executedSize + executionSize >= order.sizeAmount ||
                order.tradeType == TradingTypes.TradeType.MARKET
                ? order.collateral
                : int256(0);
        }
        // check position and leverage
        (uint256 afterPosition, ) = position.validLeverage(
            pair,
            executionPrice,
            collateral,
            executionSize,
            true,
            tradingConfig.maxLeverage,
            tradingConfig.maxPositionAmount,
            false,
            positionManager.getFundingFee(order.account, order.pairIndex, order.isLong)
        );
        require(afterPosition > 0, "zpa");

        // increase position
        (uint256 tradingFee, int256 fundingFee) = positionManager.increasePosition(
            pairIndex,
            order.orderId,
            order.account,
            keeper,
            executionSize,
            order.isLong,
            collateral,
            feeCollector.getTradingFeeTier(pairIndex, tier),
            referralsRatio,
            referralUserRatio,
            referralOwner,
            executionPrice
        );

        // add executed size
        order.executedSize += executionSize;
        orderManager.increaseOrderExecutedSize(order.orderId, order.tradeType, true, executionSize);

        // remove order
        if (
            order.tradeType == TradingTypes.TradeType.MARKET ||
            order.executedSize >= order.sizeAmount
        ) {
            orderManager.removeOrderFromPosition(
                IOrderManager.PositionOrder(
                    order.account,
                    order.pairIndex,
                    order.isLong,
                    true,
                    order.tradeType,
                    _orderId,
                    order.sizeAmount
                )
            );

            // delete order
            if (_tradeType == TradingTypes.TradeType.MARKET) {
                orderManager.removeIncreaseMarketOrders(_orderId);
            } else if (_tradeType == TradingTypes.TradeType.LIMIT) {
                orderManager.removeIncreaseLimitOrders(_orderId);
            }

            feeCollector.distributeNetworkFee(keeper, orderNetworkFee.paymentType, orderNetworkFee.networkFeeAmount);
        }

        emit ExecuteIncreaseOrder(
            order.account,
            order.orderId,
            order.pairIndex,
            order.tradeType,
            order.isLong,
            collateral,
            order.sizeAmount,
            order.openPrice,
            executionSize,
            executionPrice,
            order.executedSize,
            tradingFee,
            fundingFee,
            orderNetworkFee.paymentType,
            orderNetworkFee.networkFeeAmount
        );
    }

    function executeDecreaseOrders(
        address keeper,
        ExecuteOrder[] memory orders,
        TradingTypes.TradeType tradeType
    ) external override onlyExecutorOrSelf {
        for (uint256 i = 0; i < orders.length; i++) {
            ExecuteOrder memory order = orders[i];
            try
                this.executeDecreaseOrder(
                    keeper,
                    order.orderId,
                    tradeType,
                    order.tier,
                    order.referralsRatio,
                    order.referralUserRatio,
                    order.referralOwner,
                    false,
                    0,
                    tradeType == TradingTypes.TradeType.MARKET
                )
            {} catch Error(string memory reason) {
                emit ExecuteOrderError(order.orderId, reason);
                orderManager.cancelOrder(
                    order.orderId,
                    tradeType,
                    false,
                    reason
                );
            }
        }
    }

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
    ) external override onlyExecutorOrSelf {
        TradingTypes.OrderNetworkFee memory orderNetworkFee;
        TradingTypes.DecreasePositionOrder memory order;
        (order, orderNetworkFee) = orderManager.getDecreaseOrder(_orderId, _tradeType);
        if (order.account == address(0)) {
            emit InvalidOrder(keeper, _orderId, 'address 0');
            return;
        }

        // is expired
        if (order.tradeType == TradingTypes.TradeType.MARKET) {
            require(order.blockTime + maxTimeDelay >= block.timestamp, "order expired");
        }

        // check pair enable
        uint256 pairIndex = order.pairIndex;
        IPool.Pair memory pair = pool.getPair(pairIndex);
        if (!pair.enable) {
            orderManager.cancelOrder(order.orderId, order.tradeType, false, "!enable");
            return;
        }

        // get position
        Position.Info memory position = positionManager.getPosition(
            order.account,
            order.pairIndex,
            order.isLong
        );
        if (position.positionAmount == 0) {
            orderManager.cancelAllPositionOrders(order.account, order.pairIndex, order.isLong);
            return;
        }

        IPool.TradingConfig memory tradingConfig = pool.getTradingConfig(pairIndex);

        if (executionSize == 0) {
            executionSize = order.sizeAmount - order.executedSize;
//            if (executionSize > tradingConfig.maxTradeAmount && !isSystem) {
//                executionSize = tradingConfig.maxTradeAmount;
//            }
        }

        // valid order size
        executionSize = Math.min(executionSize, position.positionAmount);

        // validate can be triggered
        uint256 executionPrice = TradingHelper.getValidPrice(
            ADDRESS_PROVIDER,
            pair.indexToken,
            tradingConfig
        );
        ValidationHelper.validatePriceTriggered(
            tradingConfig,
            order.tradeType,
            order.abovePrice,
            executionPrice,
            order.triggerPrice,
            order.maxSlippage
        );

//        bytes32 positionKey = positionManager.getPositionKey(order.account, order.pairIndex, order.isLong);
//        require(!positionManager.needLiquidation(positionKey, executionPrice), "need liquidation");

        // compare openPrice and oraclePrice
        if (order.tradeType == TradingTypes.TradeType.LIMIT) {
            if (!order.isLong) {
                executionPrice = Math.min(order.triggerPrice, executionPrice);
            } else {
                executionPrice = Math.max(order.triggerPrice, executionPrice);
            }
        }

        // check position and leverage
        position.validLeverage(
            pair,
            executionPrice,
            order.collateral,
            executionSize,
            false,
            tradingConfig.maxLeverage,
            tradingConfig.maxPositionAmount,
            isSystem,
            positionManager.getFundingFee(order.account, order.pairIndex, order.isLong)
        );

        (bool _needADL, ) = positionManager.needADL(
            order.pairIndex,
            order.isLong,
            executionSize,
            executionPrice
        );
        if (_needADL) {
            orderManager.setOrderNeedADL(_orderId, order.tradeType, _needADL);

            emit ExecuteDecreaseOrder(
                order.account,
                _orderId,
                pairIndex,
                order.tradeType,
                order.isLong,
                order.collateral,
                order.sizeAmount,
                order.triggerPrice,
                executionSize,
                executionPrice,
                order.executedSize,
                _needADL,
                0,
                0,
                0,
                TradingTypes.InnerPaymentType.NONE,
                0
            );
            return;
        }

        int256 collateral;
        if (order.collateral > 0) {
            collateral = order.executedSize == 0 || onlyOnce ? order.collateral : int256(0);
        } else {
            collateral = order.executedSize + executionSize >= order.sizeAmount || onlyOnce
                ? order.collateral
                : int256(0);
        }

        (uint256 tradingFee, int256 fundingFee, int256 pnl) = positionManager.decreasePosition(
            pairIndex,
            order.orderId,
            order.account,
            keeper,
            executionSize,
            order.isLong,
            collateral,
            feeCollector.getTradingFeeTier(pairIndex, tier),
            referralsRatio,
            referralUserRatio,
            referralOwner,
            executionPrice,
            false
        );

        // add executed size
        order.executedSize += executionSize;
        orderManager.increaseOrderExecutedSize(
            order.orderId,
            order.tradeType,
            false,
            executionSize
        );

        position = positionManager.getPosition(order.account, order.pairIndex, order.isLong);
        // remove order
        if (onlyOnce || order.executedSize >= order.sizeAmount || position.positionAmount == 0) {
            // remove decrease order
            orderManager.removeOrderFromPosition(
                IOrderManager.PositionOrder(
                    order.account,
                    order.pairIndex,
                    order.isLong,
                    false,
                    order.tradeType,
                    order.orderId,
                    executionSize
                )
            );

            // delete order
            if (order.tradeType == TradingTypes.TradeType.MARKET) {
                orderManager.removeDecreaseMarketOrders(_orderId);
            } else if (order.tradeType == TradingTypes.TradeType.LIMIT) {
                orderManager.removeDecreaseLimitOrders(_orderId);
            } else {
                orderManager.removeDecreaseLimitOrders(_orderId);
            }

            feeCollector.distributeNetworkFee(keeper, orderNetworkFee.paymentType, orderNetworkFee.networkFeeAmount);
        }

        if (position.positionAmount == 0) {
            // cancel all decrease order
            IOrderManager.PositionOrder[] memory orders = orderManager.getPositionOrders(
                PositionKey.getPositionKey(order.account, order.pairIndex, order.isLong)
            );

            for (uint256 i = 0; i < orders.length; i++) {
                IOrderManager.PositionOrder memory positionOrder = orders[i];
                orderManager.cancelOrder(
                    positionOrder.orderId,
                    positionOrder.tradeType,
                    positionOrder.isIncrease,
                    "closed position"
                );
            }
        }

        emit ExecuteDecreaseOrder(
            order.account,
            _orderId,
            pairIndex,
            order.tradeType,
            order.isLong,
            collateral,
            order.sizeAmount,
            order.triggerPrice,
            executionSize,
            executionPrice,
            order.executedSize,
            _needADL,
            pnl,
            tradingFee,
            fundingFee,
            orderNetworkFee.paymentType,
            orderNetworkFee.networkFeeAmount
        );
    }

    function executeADLAndDecreaseOrders(
        address keeper,
        uint256 pairIndex,
        ExecutePosition[] memory executePositions,
        IExecutionLogic.ExecuteOrder[] memory executeOrders
    ) external override onlyExecutorOrSelf {
        uint256 longOrderSize;
        uint256 shortOrderSize;
        for (uint256 i = 0; i < executeOrders.length; i++) {
            IExecutionLogic.ExecuteOrder memory executeOrder = executeOrders[i];
            (TradingTypes.DecreasePositionOrder memory order,) = orderManager.getDecreaseOrder(
                executeOrder.orderId,
                executeOrder.tradeType
            );
            require(order.pairIndex == pairIndex, "mismatch pairIndex");
            if (order.isLong) {
                longOrderSize += order.sizeAmount - order.executedSize;
            } else {
                shortOrderSize += order.sizeAmount - order.executedSize;
            }
        }

        IPool.TradingConfig memory tradingConfig = pool.getTradingConfig(pairIndex);
        IPool.Pair memory pair = pool.getPair(pairIndex);
        // execution price
        uint256 executionPrice = TradingHelper.getValidPrice(
            ADDRESS_PROVIDER,
            pair.indexToken,
            tradingConfig
        );

        uint256 totalNeedADLAmount;
        if (longOrderSize > shortOrderSize) {
            (, totalNeedADLAmount) = positionManager.needADL(pairIndex, true, longOrderSize - shortOrderSize, executionPrice);
        } else if (longOrderSize < shortOrderSize) {
            (, totalNeedADLAmount) = positionManager.needADL(pairIndex, false, shortOrderSize - longOrderSize, executionPrice);
        }

        uint256[] memory adlOrderIds = new uint256[](executePositions.length);
        bytes32[] memory adlPositionKeys = new bytes32[](executePositions.length);
        if (totalNeedADLAmount > 0) {
            uint256 executeTotalAmount;
            ExecutePositionInfo[] memory adlPositions = new ExecutePositionInfo[](executePositions.length);
            for (uint256 i = 0; i < executePositions.length; i++) {
                if (executeTotalAmount == totalNeedADLAmount) {
                    break;
                }
                ExecutePosition memory executePosition = executePositions[i];
                Position.Info memory position = positionManager.getPositionByKey(executePosition.positionKey);
                require(position.pairIndex == pairIndex, "mismatch pairIndex");

                uint256 adlExecutionSize;
                if (position.positionAmount >= totalNeedADLAmount - executeTotalAmount) {
                    adlExecutionSize = totalNeedADLAmount - executeTotalAmount;
                } else {
                    adlExecutionSize = position.positionAmount;
                }
                if (adlExecutionSize > 0) {
                    executeTotalAmount += adlExecutionSize;

                    ExecutePositionInfo memory adlPosition = adlPositions[i];
                    adlPosition.position = position;
                    adlPosition.executionSize = adlExecutionSize;
                    adlPosition.tier = executePosition.tier;
                    adlPosition.referralsRatio = executePosition.referralsRatio;
                    adlPosition.referralUserRatio = executePosition.referralUserRatio;
                    adlPosition.referralOwner = executePosition.referralOwner;
                }
            }

            for (uint256 i = 0; i < adlPositions.length; i++) {
                ExecutePositionInfo memory adlPosition = adlPositions[i];
                if (adlPosition.executionSize > 0) {
                    uint256 orderId = orderManager.createOrder(
                        TradingTypes.CreateOrderRequest({
                            account: adlPosition.position.account,
                            pairIndex: adlPosition.position.pairIndex,
                            tradeType: TradingTypes.TradeType.MARKET,
                            collateral: 0,
                            openPrice: executionPrice,
                            isLong: adlPosition.position.isLong,
                            sizeAmount: -(adlPosition.executionSize.safeConvertToInt256()),
                            maxSlippage: 0,
                            paymentType: TradingTypes.InnerPaymentType.NONE,
                            networkFeeAmount: 0,
                            data: abi.encode(adlPosition.position.account)
                        })
                    );
                    this.executeDecreaseOrder(
                        keeper,
                        orderId,
                        TradingTypes.TradeType.MARKET,
                        adlPosition.tier,
                        adlPosition.referralsRatio,
                        adlPosition.referralUserRatio,
                        adlPosition.referralOwner,
                        true,
                        0,
                        true
                    );
                    adlOrderIds[i] = orderId;
                    adlPositionKeys[i] = PositionKey.getPositionKey(
                        adlPosition.position.account,
                        adlPosition.position.pairIndex,
                        adlPosition.position.isLong
                    );
                }
            }
        }

        uint256[] memory orders = new uint256[](executeOrders.length);
        for (uint256 i = 0; i < executeOrders.length; i++) {
            IExecutionLogic.ExecuteOrder memory executeOrder = executeOrders[i];

            (TradingTypes.DecreasePositionOrder memory order,) = orderManager.getDecreaseOrder(
                executeOrder.orderId,
                executeOrder.tradeType
            );

            // execution size
            uint256 executionSize = order.sizeAmount - order.executedSize;

            if (order.tradeType == TradingTypes.TradeType.LIMIT) {
                if (!order.isLong) {
                    executionPrice = Math.min(order.triggerPrice, executionPrice);
                } else {
                    executionPrice = Math.max(order.triggerPrice, executionPrice);
                }
            }

            orders[i] = executeOrder.orderId;

            (bool _needADL, uint256 needADLAmount) = positionManager.needADL(
                order.pairIndex,
                order.isLong,
                executionSize,
                executionPrice
            );
            if (!_needADL && !order.needADL) {
                this.executeDecreaseOrder(
                    keeper,
                    order.orderId,
                    order.tradeType,
                    executeOrder.tier,
                    executeOrder.referralsRatio,
                    executeOrder.referralUserRatio,
                    executeOrder.referralOwner,
                    false,
                    0,
                    executeOrder.tradeType == TradingTypes.TradeType.MARKET
                );
            } else {
                this.executeDecreaseOrder(
                    keeper,
                    order.orderId,
                    order.tradeType,
                    executeOrder.tier,
                    executeOrder.referralsRatio,
                    executeOrder.referralUserRatio,
                    executeOrder.referralOwner,
                    true,
                    executionSize - needADLAmount,
                    false
                );
            }
        }

        emit ExecuteAdlOrder(adlOrderIds, adlPositionKeys, orders);
    }
}
