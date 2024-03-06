// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IPythOraclePriceFeed.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/IPythOracle.sol";
import "../interfaces/IBacktracker.sol";

contract PythOraclePriceFeed is IPythOraclePriceFeed {
    IAddressesProvider public immutable ADDRESS_PROVIDER;
    uint256 public immutable PRICE_DECIMALS = 30;

    uint256 public priceAge;

    IPythOracle public pyth;
    address public executor;

    mapping(address => bytes32) public tokenPriceIds;
    mapping(bytes32 => address) public priceIdTokens;

    // blockTime + backtrackRound => token => price
    mapping(bytes32 => mapping(address => uint256)) public backtrackTokenPrices;

    constructor(
        IAddressesProvider addressProvider,
        address _pyth,
        address[] memory tokens,
        bytes32[] memory priceIds
    ) {
        priceAge = 10;
        ADDRESS_PROVIDER = addressProvider;
        pyth = IPythOracle(_pyth);
        _setTokenPriceIds(tokens, priceIds);
    }

    modifier onlyPoolAdmin() {
        require(IRoleManager(ADDRESS_PROVIDER.roleManager()).isPoolAdmin(msg.sender), "opa");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "only executor");
        _;
    }

    modifier onlyBacktracking() {
        require(IBacktracker(ADDRESS_PROVIDER.backtracker()).backtracking(), "only backtracking");
        _;
    }

    function updateExecutorAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = executor;
        executor = newAddress;
        emit UpdatedExecutorAddress(msg.sender, oldAddress, newAddress);
    }

    function updatePriceAge(uint256 age) external onlyPoolAdmin {
        uint256 oldAge = priceAge;
        priceAge = age;
        emit PriceAgeUpdated(oldAge, priceAge);
    }

    function updatePythAddress(IPythOracle _pyth) external onlyPoolAdmin {
        address oldAddress = address(pyth);
        pyth = _pyth;
        emit PythAddressUpdated(oldAddress, address(pyth));
    }

    function setTokenPriceIds(
        address[] memory tokens,
        bytes32[] memory priceIds
    ) external onlyPoolAdmin {
        _setTokenPriceIds(tokens, priceIds);
    }

    function updatePrice(
        address[] calldata tokens,
        bytes[] calldata updateData,
        uint64[] calldata publishTimes
    ) external payable override {
        uint fee = pyth.getUpdateFee(updateData);
        if (msg.value < fee) {
            revert("insufficient fee");
        }
        bytes32[] memory priceIds = new bytes32[](tokens.length);
        bool update = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "zero token address");
            require(tokenPriceIds[tokens[i]] != 0, "unknown price id");

            priceIds[i] = tokenPriceIds[tokens[i]];

            if (pyth.latestPriceInfoPublishTime(tokenPriceIds[tokens[i]]) < publishTimes[i]) {
                update = true;
            }
        }

        if (update && priceIds.length > 0) {
            pyth.updatePriceFeedsIfNecessary{value: fee}(updateData, priceIds, publishTimes);
        }
    }

    function updateHistoricalPrice(
        address[] calldata tokens,
        bytes[] calldata updateData,
        uint64 publishTime
    ) external payable onlyExecutor onlyBacktracking override {
        uint fee = pyth.getUpdateFee(updateData);
        if (msg.value < fee) {
            revert("insufficient fee");
        }
        bytes32[] memory priceIds = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "zero token address");
            require(tokenPriceIds[tokens[i]] != 0, "unknown price id");

            priceIds[i] = tokenPriceIds[tokens[i]];
        }
        PythStructs.PriceFeed[] memory priceFeeds;
        try pyth.parsePriceFeedUpdates{value: msg.value}(updateData, priceIds, publishTime, publishTime) returns (PythStructs.PriceFeed[] memory _priceFeeds) {
            priceFeeds = _priceFeeds;
        } catch {
            revert("parse price failed");
        }
        for (uint256 i = 0; i < priceFeeds.length; i++) {
            PythStructs.PriceFeed memory priceFeed = priceFeeds[i];

            address token = priceIdTokens[priceFeed.id];
            bytes32 backtrackRound = bytes32(abi.encodePacked(uint64(block.timestamp), publishTime));
            backtrackTokenPrices[backtrackRound][token] = _returnPriceWithDecimals(priceFeed.price);
        }
    }

    function removeHistoricalPrice(
        uint64 _backtrackRound,
        address[] calldata tokens
    ) external onlyExecutor onlyBacktracking {
        bytes32 backtrackRound = bytes32(abi.encodePacked(uint64(block.timestamp), _backtrackRound));
        for (uint256 i = 0; i < tokens.length; i++) {
            delete backtrackTokenPrices[backtrackRound][tokens[i]];
        }
    }

    function getHistoricalPrice(
        uint64 publishTime,
        address token
    ) external view onlyBacktracking override returns (uint256) {
        bytes32 backtrackRound = bytes32(abi.encodePacked(uint64(block.timestamp), publishTime));
        uint256 price = backtrackTokenPrices[backtrackRound][token];
        if (price == 0) {
            revert("invalid price");
        }
        return price;
    }

    function getPythPriceUnsafe(address token) external view returns (PythStructs.Price memory) {
        bytes32 priceId = _getPriceId(token);
        return pyth.getPriceUnsafe(priceId);
    }

    function getPythPriceNoOlderThan(address token, uint256 _priceAge) external view returns (PythStructs.Price memory) {
        bytes32 priceId = _getPriceId(token);
        return pyth.getPriceNoOlderThan(priceId, _priceAge);
    }

    function getPythPrice(address token) external view returns (PythStructs.Price memory) {
        bytes32 priceId = _getPriceId(token);
        return pyth.getPrice(priceId);
    }

    function getPrice(address token) external view override returns (uint256) {
        bytes32 priceId = _getPriceId(token);
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceId);
        return _returnPriceWithDecimals(pythPrice);
    }

    function getPriceSafely(address token) external view override returns (uint256) {
        bytes32 priceId = _getPriceId(token);
        PythStructs.Price memory pythPrice;
        try pyth.getPriceNoOlderThan(priceId, priceAge) returns (PythStructs.Price memory _pythPrice) {
            pythPrice = _pythPrice;
        } catch {
            revert("get price failed");
        }
        return _returnPriceWithDecimals(pythPrice);
    }

    function _getPriceId(address token) internal view returns (bytes32) {
        require(token != address(0), "zero token address");
        bytes32 priceId = tokenPriceIds[token];
        require(priceId != 0, "unknown price id");
        return priceId;
    }

    function _returnPriceWithDecimals(
        PythStructs.Price memory pythPrice
    ) internal pure returns (uint256) {
        if (pythPrice.price <= 0) {
            revert("invalid price");
        }
        uint256 _decimals = pythPrice.expo < 0 ? uint256(uint32(- pythPrice.expo)) : uint256(uint32(pythPrice.expo));
        return uint256(uint64(pythPrice.price)) * (10 ** (PRICE_DECIMALS - _decimals));
    }

    function _setTokenPriceIds(address[] memory tokens, bytes32[] memory priceIds) internal {
        require(tokens.length == priceIds.length, "inconsistent params length");
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPriceIds[tokens[i]] = priceIds[i];
            priceIdTokens[priceIds[i]] = tokens[i];
            emit TokenPriceIdUpdated(tokens[i], priceIds[i]);
        }
    }

    function decimals() public pure override returns (uint256) {
        return PRICE_DECIMALS;
    }
}
