// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../interfaces/IUiPoolDataProvider.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPositionManager.sol";
import "../interfaces/IPoolView.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IOrderManager.sol";

contract UiPoolDataProvider is IUiPoolDataProvider {

    IAddressesProvider public immutable ADDRESS_PROVIDER;

    constructor(IAddressesProvider addressProvider){
        ADDRESS_PROVIDER = addressProvider;
    }

    function getPairsData(
        IPool pool,
        IPoolView poolView,
        IOrderManager orderManager,
        IPositionManager positionManager,
        IRouter router,
        IFeeCollector feeCollector,
        uint256[] memory pairIndexes,
        uint256[] memory prices
    ) public view returns (PairData[] memory) {
        require(pairIndexes.length == prices.length, "nl");

        PairData[] memory pairsData = new PairData[](pairIndexes.length);
        for (uint256 i = 0; i < pairIndexes.length; i++) {
            uint256 pairIndex = pairIndexes[i];
            uint256 price = prices[i];
            PairData memory pairData = pairsData[i];

            IPool.Pair memory pair = pool.getPair(pairIndex);
            pairData.pairIndex = pair.pairIndex;
            pairData.indexToken = pair.indexToken;
            pairData.stableToken = pair.stableToken;
            pairData.pairToken = pair.pairToken;
            pairData.enable = pair.enable;
            pairData.kOfSwap = pair.kOfSwap;
            pairData.expectIndexTokenP = pair.expectIndexTokenP;
            pairData.maxUnbalancedP = pair.maxUnbalancedP;
            pairData.unbalancedDiscountRate = pair.unbalancedDiscountRate;
            pairData.addLpFeeP = pair.addLpFeeP;
            pairData.removeLpFeeP = pair.removeLpFeeP;

            IRouter.OperationStatus memory operationStatus = router.getOperationStatus(pairIndex);
            pairData.increasePositionIsEnabled = !operationStatus.increasePositionDisabled;
            pairData.decreasePositionIsEnabled = !operationStatus.decreasePositionDisabled;
            pairData.orderIsEnabled = !operationStatus.orderDisabled;
            pairData.addLiquidityIsEnabled = !operationStatus.addLiquidityDisabled;
            pairData.removeLiquidityIsEnabled = !operationStatus.removeLiquidityDisabled;

            IPool.TradingConfig memory tradingConfig = pool.getTradingConfig(pairIndex);
            pairData.minLeverage = tradingConfig.minLeverage;
            pairData.maxLeverage = tradingConfig.maxLeverage;
            pairData.minTradeAmount = tradingConfig.minTradeAmount;
            pairData.maxTradeAmount = tradingConfig.maxTradeAmount;
            pairData.maxPositionAmount = tradingConfig.maxPositionAmount;
            pairData.maintainMarginRate = tradingConfig.maintainMarginRate;
            pairData.priceSlipP = tradingConfig.priceSlipP;
            pairData.maxPriceDeviationP = tradingConfig.maxPriceDeviationP;

            IFeeCollector.TradingFeeTier memory tradingFeeTier = feeCollector.getRegularTradingFeeTier(pairIndex);
            pairData.takerFee = tradingFeeTier.takerFee;
            pairData.makerFee = tradingFeeTier.makerFee;

            IPool.TradingFeeConfig memory tradingFeeConfig = pool.getTradingFeeConfig(pairIndex);
            pairData.lpFeeDistributeP = tradingFeeConfig.lpFeeDistributeP;
            pairData.stakingFeeDistributeP = tradingFeeConfig.stakingFeeDistributeP;
            pairData.keeperFeeDistributeP = tradingFeeConfig.keeperFeeDistributeP;

            IPool.Vault memory vault = pool.getVault(pairIndex);
            pairData.indexTotalAmount = vault.indexTotalAmount;
            pairData.indexReservedAmount = vault.indexReservedAmount;
            pairData.stableTotalAmount = vault.stableTotalAmount;
            pairData.stableReservedAmount = vault.stableReservedAmount;
            pairData.poolAvgPrice = vault.averagePrice;

            pairData.longTracker = positionManager.longTracker(pairIndex);
            pairData.shortTracker = positionManager.shortTracker(pairIndex);

            pairData.currentFundingRate = positionManager.getCurrentFundingRate(pairIndex);
            pairData.nextFundingRate = positionManager.getNextFundingRate(pairIndex, price);
            pairData.nextFundingRateUpdateTime = positionManager.getNextFundingRateUpdateTime(pairIndex);

            pairData.lpPrice = poolView.lpFairPrice(pairIndex, price);
            pairData.lpTotalSupply = IERC20(pair.pairToken).totalSupply();

            pairData.networkFees = new NetworkFeeData[](2);
            NetworkFeeData memory networkFeeDataETH = pairData.networkFees[0];
            IOrderManager.NetworkFee memory ethFee = orderManager.getNetworkFee(TradingTypes.NetworkFeePaymentType.ETH, pairIndex);
            networkFeeDataETH.paymentType = TradingTypes.NetworkFeePaymentType.ETH;
            networkFeeDataETH.basicNetworkFee = ethFee.basicNetworkFee;
            networkFeeDataETH.discountThreshold = ethFee.discountThreshold;
            networkFeeDataETH.discountedNetworkFee = ethFee.discountedNetworkFee;

            NetworkFeeData memory networkFeeDataCollateral = pairData.networkFees[1];
            IOrderManager.NetworkFee memory collateralFee = orderManager.getNetworkFee(TradingTypes.NetworkFeePaymentType.COLLATERAL, pairIndex);
            networkFeeDataCollateral.paymentType = TradingTypes.NetworkFeePaymentType.COLLATERAL;
            networkFeeDataCollateral.basicNetworkFee = collateralFee.basicNetworkFee;
            networkFeeDataCollateral.discountThreshold = collateralFee.discountThreshold;
            networkFeeDataCollateral.discountedNetworkFee = collateralFee.discountedNetworkFee;
        }

        return pairsData;
    }

    function getUserTokenData(
        IERC20Metadata[] memory tokens,
        address user
    ) external view returns (UserTokenData[] memory) {
        UserTokenData[] memory userTokensData = new UserTokenData[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            UserTokenData memory userTokenData = userTokensData[i];
            userTokenData.token = address(tokens[i]);
            if (address(tokens[i]) == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                userTokenData.name = "";
                userTokenData.symbol = "";
                userTokenData.decimals = 18;
                userTokenData.totalSupply = 0;
                if (user != address(0)) {
                    userTokenData.balance = user.balance;
                }
            } else {
                userTokenData.name = tokens[i].name();
                userTokenData.symbol = tokens[i].symbol();
                userTokenData.decimals = tokens[i].decimals();
                userTokenData.totalSupply = tokens[i].totalSupply();
                if (user != address(0)) {
                    userTokenData.balance = tokens[i].balanceOf(user);
                }
            }
        }
        return userTokensData;
    }
}
