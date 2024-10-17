// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/Upgradeable.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IFundingRate.sol";
import "../interfaces/IOrderManager.sol";
import "../interfaces/IPositionManager.sol";
import "../interfaces/IPythOraclePriceFeed.sol";
import "../interfaces/IConfigurationProvider.sol";
import "../interfaces/IPool.sol";

contract Facet is Ownable, Upgradeable {

    address public fundingRate;
    address public orderManager;
    address public positionManager;
    address public pool;
    address public pythOraclePriceFeed;
    address public configurationProvider;

    function initialize(
        IAddressesProvider addressProvider,
        address owner
    ) public initializer {
        ADDRESS_PROVIDER = addressProvider;
        _transferOwnership(owner);
    }

    function setAddresses(
        address _fundingRate,
        address _orderManager,
        address _positionManager,
        address _pool,
        address _pythOraclePriceFeed,
        address _configurationProvider
    ) external onlyOwner {
        if (_fundingRate != address(0)) {
            fundingRate = _fundingRate;
        }

        if (_orderManager != address(0)) {
            orderManager = _orderManager;
        }

        if (_positionManager != address(0)) {
            positionManager = _positionManager;
        }

        if (_pool != address(0)) {
            pool = _pool;
        }

        if (_pythOraclePriceFeed != address(0)) {
            pythOraclePriceFeed = _pythOraclePriceFeed;
        }

        if (_configurationProvider != address(0)) {
            configurationProvider = _configurationProvider;
        }
    }

    function erc20(address target) external view returns (string memory name, string memory symbol, uint8 decimals) {
        IERC20Metadata token = IERC20Metadata(target);
        return (token.name(), token.symbol(), token.decimals());
    }

    struct FundingFeeConfigV2Ext {
        int256 growthRateLow;
        int256 growthRateHigh;
        uint256 range;
        int256 maxRate;
        uint256 fundingInterval;
        int256 baseRate;
        uint256 baseRateMaximum;
    }

    function getFundingFeeConfigs(
        uint256 pairIndex
    ) external view returns (FundingFeeConfigV2Ext memory) {
        (bool success, bytes memory data) = fundingRate.staticcall(abi.encodeWithSignature("fundingFeeConfigsV2(uint256)", pairIndex));
        require(success, "static call failed");
        IFundingRate.FundingFeeConfigV2 memory fundingFeeConfigV2 = abi.decode(data, (IFundingRate.FundingFeeConfigV2));

        IConfigurationProvider _configurationProvider = IConfigurationProvider(configurationProvider);
        return FundingFeeConfigV2Ext({
            growthRateLow: fundingFeeConfigV2.growthRateLow,
            growthRateHigh: fundingFeeConfigV2.growthRateHigh,
            range: fundingFeeConfigV2.range,
            maxRate: fundingFeeConfigV2.maxRate,
            fundingInterval: fundingFeeConfigV2.fundingInterval,
            baseRate: _configurationProvider.baseFundingRate(pairIndex),
            baseRateMaximum: _configurationProvider.baseFundingRateMaximum(pairIndex)
        });
    }

    function getNetworkFee(
        TradingTypes.NetworkFeePaymentType paymentType,
        uint256 pairIndex
    ) external view returns (IOrderManager.NetworkFee memory) {
        return IOrderManager(orderManager).getNetworkFee(paymentType, pairIndex);
    }

    function getPair(uint256 pairIndex) external view returns (IPool.Pair memory) {
        return IPool(pool).getPair(pairIndex);
    }

    function getTradingConfig(uint256 pairIndex) external view returns (IPool.TradingConfig memory) {
        return IPool(pool).getTradingConfig(pairIndex);
    }

    function getTradingFeeConfig(uint256 pairIndex) external view returns (IPool.TradingFeeConfig memory) {
        return IPool(pool).getTradingFeeConfig(pairIndex);
    }

    function getTokenPriceIds(address token) external view returns (bytes32 priceId) {
        return IPythOraclePriceFeed(pythOraclePriceFeed).tokenPriceIds(token);
    }

    struct FundingFee {
        int256 currentFundingRate;
        int256 nextFundingRate;
        uint256 nextFundingRateUpdateTime;
    }

    function getFundingFee(
        uint256 pairIndex
    ) external view returns (FundingFee memory) {
        IPool.Pair memory pair = IPool(pool).getPair(pairIndex);
        uint256 price = IPythOraclePriceFeed(pythOraclePriceFeed).getPrice(pair.indexToken);

        IPositionManager positionManagerContract = IPositionManager(positionManager);
        return FundingFee({
            currentFundingRate: positionManagerContract.getCurrentFundingRate(pairIndex),
            nextFundingRate: positionManagerContract.getNextFundingRate(pairIndex, price),
            nextFundingRateUpdateTime: positionManagerContract.getNextFundingRateUpdateTime(pairIndex)
        });
    }

}
