// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/PrecisionUtils.sol";
import "../libraries/PositionKey.sol";
import "../libraries/Int256Utils.sol";
import "../libraries/Upgradeable.sol";
import "../libraries/TradingTypes.sol";

import "../helpers/ValidationHelper.sol";

import "../interfaces/IPriceFeed.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IOrderManager.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/IPositionManager.sol";
import "../interfaces/IOrderCallback.sol";

contract OrderManager is IOrderManager, Upgradeable {
    using SafeERC20 for IERC20;
    using PrecisionUtils for uint256;
    using Math for uint256;
    using SafeMath for uint256;
    using Int256Utils for int256;
    using Int256Utils for uint256;
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    uint256 public override ordersIndex;

    mapping(uint256 => TradingTypes.IncreasePositionOrder) public increaseMarketOrders;
    mapping(uint256 => TradingTypes.DecreasePositionOrder) public decreaseMarketOrders;
    mapping(uint256 => TradingTypes.IncreasePositionOrder) public increaseLimitOrders;
    mapping(uint256 => TradingTypes.DecreasePositionOrder) public decreaseLimitOrders;
    mapping(uint256 => TradingTypes.OrderNetworkFee) public orderNetworkFees;

    // positionKey
    mapping(bytes32 => PositionOrder[]) public positionOrders;
    mapping(bytes32 => mapping(uint256 => uint256)) public positionOrderIndex;

    mapping(TradingTypes.NetworkFeePaymentType => mapping(uint256 => NetworkFee)) public networkFees;

    IPool public pool;
    IPositionManager public positionManager;
    address public router;

    function initialize(
        IAddressesProvider addressProvider,
        IPool _pool,
        IPositionManager _positionManager
    ) public initializer {
        ADDRESS_PROVIDER = addressProvider;
        pool = _pool;
        positionManager = _positionManager;
    }

    modifier onlyRouter() {
        require(msg.sender == router, "onlyRouter");
        _;
    }

    modifier onlyExecutor() {
        require(
            msg.sender == ADDRESS_PROVIDER.executionLogic() ||
                msg.sender == ADDRESS_PROVIDER.liquidationLogic(),
            "onlyExecutor"
        );
        _;
    }

    modifier onlyExecutorAndRouter() {
        require(
            msg.sender == router ||
            msg.sender == ADDRESS_PROVIDER.executionLogic() ||
            msg.sender == ADDRESS_PROVIDER.liquidationLogic(),
            "onlyExecutor&Router"
        );
        _;
    }

    function setRouter(address _router) external onlyPoolAdmin {
        address oldAddress = router;
        router = _router;
        emit UpdateRouterAddress(msg.sender, oldAddress, _router);
    }

    function updateNetworkFees(
        TradingTypes.NetworkFeePaymentType[] memory paymentTypes,
        uint256[] memory pairIndexes,
        NetworkFee[] memory fees
    ) external onlyPoolAdmin {
        require(paymentTypes.length == pairIndexes.length && pairIndexes.length == fees.length, "inconsistent params length");

        for (uint256 i = 0; i < fees.length; i++) {
            _updateNetworkFee(paymentTypes[i], pairIndexes[i], fees[i]);
        }
    }

    function _updateNetworkFee(
        TradingTypes.NetworkFeePaymentType paymentType,
        uint256 pairIndex,
        NetworkFee memory fee
    ) internal {
        networkFees[paymentType][pairIndex] = fee;
        emit UpdatedNetworkFee(msg.sender, paymentType, pairIndex, fee.basicNetworkFee, fee.discountThreshold, fee.discountedNetworkFee);
    }

    function getNetworkFee(TradingTypes.NetworkFeePaymentType paymentType, uint256 pairIndex) external view override returns (NetworkFee memory) {
        return networkFees[paymentType][pairIndex];
    }

    function createOrder(
        TradingTypes.CreateOrderRequest calldata request
    ) public payable onlyExecutorAndRouter returns (uint256 orderId) {
        address account = request.account;

        // account is frozen
        ValidationHelper.validateAccountBlacklist(ADDRESS_PROVIDER, account);

        // pair enabled
        IPool.Pair memory pair = pool.getPair(request.pairIndex);
        require(pair.enable, "disabled");

        // network fees
        int256 collateral = request.collateral;
        if (request.paymentType == TradingTypes.InnerPaymentType.ETH) {
            NetworkFee memory networkFee = networkFees[TradingTypes.NetworkFeePaymentType.ETH][request.pairIndex];
            if (networkFee.basicNetworkFee > 0) {
                if ((request.sizeAmount.abs() >= networkFee.discountThreshold && msg.value < networkFee.discountedNetworkFee)
                    || (request.sizeAmount.abs() < networkFee.discountThreshold && msg.value < networkFee.basicNetworkFee)) {
                    revert("insufficient network fee");
                }
                (bool success, ) = address(pool).call{value: msg.value}(new bytes(0));
                require(success, "transfer eth failed");
            }
        } else if (request.paymentType == TradingTypes.InnerPaymentType.COLLATERAL) {
            NetworkFee memory networkFee = networkFees[TradingTypes.NetworkFeePaymentType.COLLATERAL][request.pairIndex];
            if (networkFee.basicNetworkFee > 0) {
                if ((request.sizeAmount.abs() >= networkFee.discountThreshold && request.networkFeeAmount < networkFee.discountedNetworkFee)
                    || (request.sizeAmount.abs() < networkFee.discountThreshold && request.networkFeeAmount < networkFee.basicNetworkFee)) {
                    revert("insufficient network fee");
                }
                _transferOrderCollateral(
                    pair.stableToken,
                    request.networkFeeAmount,
                    address(pool),
                    request.data
                );
            }
        }

        if (
            request.tradeType == TradingTypes.TradeType.MARKET ||
            request.tradeType == TradingTypes.TradeType.LIMIT
        ) {
            IPool.TradingConfig memory tradingConfig = pool.getTradingConfig(request.pairIndex);
            if (request.sizeAmount >= 0) {
                require(
                    request.sizeAmount == 0 ||
                        (request.sizeAmount.abs() >= tradingConfig.minTradeAmount &&
                            request.sizeAmount.abs() <= tradingConfig.maxTradeAmount),
                    "invalid trade size"
                );
            }
        }

        // transfer collateral
        if (collateral > 0) {
            _transferOrderCollateral(
                pair.stableToken,
                collateral.abs(),
                address(pool),
                request.data
            );
        }

        if (request.sizeAmount > 0) {
            return
                _saveIncreaseOrder(
                    TradingTypes.IncreasePositionRequest({
                        account: account,
                        pairIndex: request.pairIndex,
                        tradeType: request.tradeType,
                        collateral: collateral,
                        openPrice: request.openPrice,
                        isLong: request.isLong,
                        sizeAmount: request.sizeAmount.abs(),
                        maxSlippage: request.maxSlippage,
                        paymentType: TradingTypes.NetworkFeePaymentType.ETH,
                        networkFeeAmount: request.networkFeeAmount
                    }),
                    request.paymentType
                );
        } else if (request.sizeAmount < 0) {
            return
                _saveDecreaseOrder(
                    TradingTypes.DecreasePositionRequest({
                        account: account,
                        pairIndex: request.pairIndex,
                        tradeType: request.tradeType,
                        collateral: collateral,
                        triggerPrice: request.openPrice,
                        sizeAmount: request.sizeAmount.abs(),
                        isLong: request.isLong,
                        maxSlippage: request.maxSlippage,
                        paymentType: TradingTypes.NetworkFeePaymentType.ETH,
                        networkFeeAmount: request.networkFeeAmount
                    }),
                    request.paymentType
                );
        } else {
            require(collateral != 0, "collateral required");
            return
                _saveIncreaseOrder(
                    TradingTypes.IncreasePositionRequest({
                        account: account,
                        pairIndex: request.pairIndex,
                        tradeType: request.tradeType,
                        collateral: collateral,
                        openPrice: request.openPrice,
                        isLong: request.isLong,
                        sizeAmount: 0,
                        maxSlippage: request.maxSlippage,
                        paymentType: TradingTypes.NetworkFeePaymentType.ETH,
                        networkFeeAmount: request.networkFeeAmount
                    }),
                    request.paymentType
                );
        }
    }

    function cancelOrder(
        uint256 orderId,
        TradingTypes.TradeType tradeType,
        bool isIncrease,
        string memory reason
    ) external onlyExecutorAndRouter {
        _cancelOrder(orderId, tradeType, isIncrease, reason);
    }

    function _cancelOrder(
        uint256 orderId,
        TradingTypes.TradeType tradeType,
        bool isIncrease,
        string memory reason
    ) private {
        if (isIncrease) {
            (TradingTypes.IncreasePositionOrder memory order,) = getIncreaseOrder(orderId, tradeType);
            if (order.account == address(0)) {
                return;
            }
            _cancelIncreaseOrder(order);
        } else {
            (TradingTypes.DecreasePositionOrder memory order,) = getDecreaseOrder(orderId, tradeType);
            if (order.account == address(0)) {
                return;
            }
            _cancelDecreaseOrder(order);
        }
        emit CancelOrder(orderId, tradeType, reason);
    }

    function cancelAllPositionOrders(
        address account,
        uint256 pairIndex,
        bool isLong
    ) external onlyExecutor {
        ValidationHelper.validateAccountBlacklist(ADDRESS_PROVIDER, account);

        bytes32 key = PositionKey.getPositionKey(account, pairIndex, isLong);

        uint256 total = positionOrders[key].length;
        uint256 count = total > 256 ? 256 : total;

        for (uint256 i = 1; i <= count; i++) {
            PositionOrder memory positionOrder = positionOrders[key][count - i];
            _cancelOrder(
                positionOrder.orderId,
                positionOrder.tradeType,
                positionOrder.isIncrease,
                "cancelAllPositionOrders"
            );
        }
    }

    function increaseOrderExecutedSize(
        uint256 orderId,
        TradingTypes.TradeType tradeType,
        bool isIncrease,
        uint256 increaseSize
    ) external override onlyExecutor {
        if (isIncrease) {
            if (tradeType == TradingTypes.TradeType.MARKET) {
                increaseMarketOrders[orderId].executedSize += increaseSize;
            } else if (tradeType == TradingTypes.TradeType.LIMIT) {
                increaseLimitOrders[orderId].executedSize += increaseSize;
            }
        } else {
            if (tradeType == TradingTypes.TradeType.MARKET) {
                decreaseMarketOrders[orderId].executedSize += increaseSize;
            } else {
                decreaseLimitOrders[orderId].executedSize += increaseSize;
            }
        }
    }

    function removeOrderFromPosition(PositionOrder memory order) public onlyExecutor {
        _removeOrderFromPosition(order);
    }

    function removeIncreaseMarketOrders(uint256 orderId) external onlyExecutor {
        delete increaseMarketOrders[orderId];
        delete orderNetworkFees[orderId];
    }

    function removeIncreaseLimitOrders(uint256 orderId) external onlyExecutor {
        delete increaseLimitOrders[orderId];
        delete orderNetworkFees[orderId];
    }

    function removeDecreaseMarketOrders(uint256 orderId) external onlyExecutor {
        delete decreaseMarketOrders[orderId];
        delete orderNetworkFees[orderId];
    }

    function removeDecreaseLimitOrders(uint256 orderId) external onlyExecutor {
        delete decreaseLimitOrders[orderId];
        delete orderNetworkFees[orderId];
    }

    function setOrderNeedADL(
        uint256 orderId,
        TradingTypes.TradeType tradeType,
        bool needADL
    ) external onlyExecutor {
        TradingTypes.DecreasePositionOrder storage order;
        if (tradeType == TradingTypes.TradeType.MARKET) {
            order = decreaseMarketOrders[orderId];
        } else {
            order = decreaseLimitOrders[orderId];
            require(order.tradeType == tradeType, "trade type not match");
        }
        order.needADL = needADL;
    }

    function _transferOrderCollateral(
        address collateral,
        uint256 collateralAmount,
        address to,
        bytes calldata data
    ) internal {
        uint256 balanceBefore = IERC20(collateral).balanceOf(to);

        if (collateralAmount > 0) {
            IOrderCallback(msg.sender).createOrderCallback(collateral, collateralAmount, to, data);
        }
        require(balanceBefore.add(collateralAmount) <= IERC20(collateral).balanceOf(to), "tc");
    }

    function _saveIncreaseOrder(
        TradingTypes.IncreasePositionRequest memory _request,
        TradingTypes.InnerPaymentType paymentType
    ) internal returns (uint256) {
        TradingTypes.IncreasePositionOrder memory order = TradingTypes.IncreasePositionOrder({
            orderId: ordersIndex,
            account: _request.account,
            pairIndex: _request.pairIndex,
            tradeType: _request.tradeType,
            collateral: _request.collateral,
            openPrice: _request.openPrice,
            isLong: _request.isLong,
            sizeAmount: _request.sizeAmount,
            executedSize: 0,
            maxSlippage: _request.maxSlippage,
            blockTime: block.timestamp
        });

        TradingTypes.OrderNetworkFee memory orderNetworkFee = TradingTypes.OrderNetworkFee({
            paymentType: paymentType,
            networkFeeAmount: _request.networkFeeAmount
        });
        orderNetworkFees[ordersIndex] = orderNetworkFee;

        if (_request.tradeType == TradingTypes.TradeType.MARKET) {
            increaseMarketOrders[ordersIndex] = order;
        } else if (_request.tradeType == TradingTypes.TradeType.LIMIT) {
            increaseLimitOrders[ordersIndex] = order;
        } else {
            revert("invalid trade type");
        }
        ordersIndex++;

        _addOrderToPosition(
            PositionOrder(
                order.account,
                order.pairIndex,
                order.isLong,
                true,
                order.tradeType,
                order.orderId,
                order.sizeAmount
            )
        );

        emit CreateIncreaseOrder(
            order.account,
            order.orderId,
            _request.pairIndex,
            _request.tradeType,
            _request.collateral,
            _request.openPrice,
            _request.isLong,
            _request.sizeAmount,
            paymentType,
            _request.networkFeeAmount
        );
        return order.orderId;
    }

    function _saveDecreaseOrder(
        TradingTypes.DecreasePositionRequest memory _request,
        TradingTypes.InnerPaymentType paymentType
    ) internal returns (uint256) {
        TradingTypes.DecreasePositionOrder memory order = TradingTypes.DecreasePositionOrder({
            orderId: ordersIndex, // orderId
            account: _request.account,
            pairIndex: _request.pairIndex,
            tradeType: _request.tradeType,
            collateral: _request.collateral,
            triggerPrice: _request.triggerPrice,
            sizeAmount: _request.sizeAmount,
            executedSize: 0,
            maxSlippage: _request.maxSlippage,
            isLong: _request.isLong,
            abovePrice: false, // abovePrice
            blockTime: block.timestamp,
            needADL: false
        });

        TradingTypes.OrderNetworkFee memory orderNetworkFee = TradingTypes.OrderNetworkFee({
            paymentType: paymentType,
            networkFeeAmount: _request.networkFeeAmount
        });
        orderNetworkFees[ordersIndex] = orderNetworkFee;

        // abovePrice
        // market：long: true,  short: false
        //  limit：long: false, short: true
        //     tp：long: false, short: true
        //     sl：long: true,  short: false
        if (_request.tradeType == TradingTypes.TradeType.MARKET) {
            order.abovePrice = _request.isLong;

            decreaseMarketOrders[ordersIndex] = order;
        } else if (_request.tradeType == TradingTypes.TradeType.LIMIT) {
            order.abovePrice = !_request.isLong;

            decreaseLimitOrders[ordersIndex] = order;
        } else if (_request.tradeType == TradingTypes.TradeType.TP) {
            order.abovePrice = !_request.isLong;

            decreaseLimitOrders[ordersIndex] = order;
        } else if (_request.tradeType == TradingTypes.TradeType.SL) {
            order.abovePrice = _request.isLong;

            decreaseLimitOrders[ordersIndex] = order;
        } else {
            revert("invalid trade type");
        }
        ordersIndex++;

        // add decrease order
        _addOrderToPosition(
            PositionOrder(
                order.account,
                order.pairIndex,
                order.isLong,
                false,
                order.tradeType,
                order.orderId,
                order.sizeAmount
            )
        );

        emit CreateDecreaseOrder(
            order.account,
            order.orderId,
            _request.tradeType,
            _request.collateral,
            _request.pairIndex,
            _request.triggerPrice,
            _request.sizeAmount,
            _request.isLong,
            order.abovePrice,
            paymentType,
            _request.networkFeeAmount
        );
        return order.orderId;
    }

    function _cancelIncreaseOrder(TradingTypes.IncreasePositionOrder memory order) internal {
        ValidationHelper.validateAccountBlacklist(ADDRESS_PROVIDER, order.account);

        _removeOrderAndRefundCollateral(
            order.account,
            order.pairIndex,
            order.executedSize == 0 ? order.collateral : int256(0),
            PositionOrder({
                account: order.account,
                pairIndex: order.pairIndex,
                isLong: order.isLong,
                isIncrease: true,
                tradeType: order.tradeType,
                orderId: order.orderId,
                sizeAmount: order.sizeAmount
            })
        );

        if (order.tradeType == TradingTypes.TradeType.MARKET) {
            delete increaseMarketOrders[order.orderId];
        } else if (order.tradeType == TradingTypes.TradeType.LIMIT) {
            delete increaseLimitOrders[order.orderId];
        }

        emit CancelIncreaseOrder(order.account, order.orderId, order.tradeType);
    }

    function _cancelDecreaseOrder(TradingTypes.DecreasePositionOrder memory order) internal {
        ValidationHelper.validateAccountBlacklist(ADDRESS_PROVIDER, order.account);

        _removeOrderAndRefundCollateral(
            order.account,
            order.pairIndex,
            order.executedSize == 0 ? order.collateral : int256(0),
            PositionOrder({
                account: order.account,
                pairIndex: order.pairIndex,
                isLong: order.isLong,
                isIncrease: false,
                tradeType: order.tradeType,
                orderId: order.orderId,
                sizeAmount: order.sizeAmount
            })
        );

        if (order.tradeType == TradingTypes.TradeType.MARKET) {
            delete decreaseMarketOrders[order.orderId];
        } else if (order.tradeType == TradingTypes.TradeType.LIMIT) {
            delete decreaseLimitOrders[order.orderId];
        } else {
            delete decreaseLimitOrders[order.orderId];
        }

        emit CancelDecreaseOrder(order.account, order.orderId, order.tradeType);
    }

    function _removeOrderAndRefundCollateral(
        address account,
        uint256 pairIndex,
        int256 collateral,
        PositionOrder memory positionOrder
    ) internal {
        _removeOrderFromPosition(positionOrder);

        if (collateral > 0) {
            IPool.Pair memory pair = pool.getPair(pairIndex);
            pool.transferTokenOrSwap(pairIndex, pair.stableToken, account, collateral.abs());
        }
    }

    function _addOrderToPosition(PositionOrder memory order) private {
        bytes32 positionKey = PositionKey.getPositionKey(
            order.account,
            order.pairIndex,
            order.isLong
        );
        positionOrderIndex[positionKey][order.orderId] = positionOrders[positionKey].length;
        positionOrders[positionKey].push(order);
    }

    function _removeOrderFromPosition(PositionOrder memory order) private {
        bytes32 positionKey = PositionKey.getPositionKey(
            order.account,
            order.pairIndex,
            order.isLong
        );

        uint256 index = positionOrderIndex[positionKey][order.orderId];
        uint256 lastIndex = positionOrders[positionKey].length - 1;

        if (index < lastIndex) {
            // swap last order
            PositionOrder memory lastOrder = positionOrders[positionKey][
                positionOrders[positionKey].length - 1
            ];

            positionOrders[positionKey][index] = lastOrder;
            positionOrderIndex[positionKey][lastOrder.orderId] = index;
        }
        delete positionOrderIndex[positionKey][order.orderId];
        positionOrders[positionKey].pop();
    }

    function getIncreaseOrder(
        uint256 orderId,
        TradingTypes.TradeType tradeType
    ) public view returns (
        TradingTypes.IncreasePositionOrder memory order,
        TradingTypes.OrderNetworkFee memory orderNetworkFee
    ) {
        if (tradeType == TradingTypes.TradeType.MARKET) {
            order = increaseMarketOrders[orderId];
        } else if (tradeType == TradingTypes.TradeType.LIMIT) {
            order = increaseLimitOrders[orderId];
        } else {
            revert("invalid trade type");
        }
        orderNetworkFee = orderNetworkFees[order.orderId];
    }

    function getDecreaseOrder(
        uint256 orderId,
        TradingTypes.TradeType tradeType
    ) public view returns (
        TradingTypes.DecreasePositionOrder memory order,
        TradingTypes.OrderNetworkFee memory orderNetworkFee
    ) {
        if (tradeType == TradingTypes.TradeType.MARKET) {
            order = decreaseMarketOrders[orderId];
        } else {
            order = decreaseLimitOrders[orderId];
        }
        orderNetworkFee = orderNetworkFees[order.orderId];
    }

    function getPositionOrders(bytes32 key) public view override returns (PositionOrder[] memory) {
        return positionOrders[key];
    }
}
