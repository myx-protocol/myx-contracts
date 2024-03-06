// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IIndexPriceFeed.sol";

import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";

contract IndexPriceFeed is IIndexPriceFeed {
    IAddressesProvider public immutable ADDRESS_PROVIDER;
    uint256 public immutable PRICE_DECIMALS = 30;
    mapping(address => uint256) public assetPrices;

    address public executor;

    constructor(
        IAddressesProvider addressProvider,
        address[] memory assets,
        uint256[] memory prices,
        address _executor
    ) {
        ADDRESS_PROVIDER = addressProvider;
        _setAssetPrices(assets, prices);
        executor = _executor;
    }

    modifier onlyExecutorOrPoolAdmin() {
        require(executor == msg.sender || IRoleManager(ADDRESS_PROVIDER.roleManager()).isPoolAdmin(msg.sender), "oep");
        _;
    }

    modifier onlyPoolAdmin() {
        require(
            IRoleManager(ADDRESS_PROVIDER.roleManager()).isPoolAdmin(msg.sender),
            "onlyPoolAdmin"
        );
        _;
    }

    function updateExecutorAddress(address _executor) external onlyPoolAdmin {
        address oldAddress = executor;
        executor = _executor;
        emit UpdateExecutorAddress(msg.sender, oldAddress, _executor);
    }

    function decimals() public pure override returns (uint256) {
        return PRICE_DECIMALS;
    }

    function updatePrice(
        address[] calldata tokens,
        uint256[] memory prices
    ) external override onlyExecutorOrPoolAdmin {
        _setAssetPrices(tokens, prices);
    }

    function getPrice(address token) external view override returns (uint256) {
        return assetPrices[token];
    }

    function getPriceSafely(address token) external view override returns (uint256) {
        return assetPrices[token];
    }

    function _setAssetPrices(address[] memory assets, uint256[] memory prices) private {
        require(assets.length == prices.length, "inconsistent params length");
        for (uint256 i = 0; i < assets.length; i++) {
            assetPrices[assets[i]] = prices[i];
            emit PriceUpdate(assets[i], prices[i], msg.sender);
        }
    }
}
