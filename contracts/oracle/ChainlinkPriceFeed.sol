// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../libraries/Roleable.sol";
import "../interfaces/IChainlinkPriceFeed.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IBacktracker.sol";

contract ChainlinkPriceFeed is IChainlinkPriceFeed, Roleable {
    using SafeMath for uint256;

    uint256 public immutable PRICE_DECIMALS = 30;
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    uint256 public priceAge;
    address public executor;

    // token -> sequencerUptimeFeed
    mapping(address => address) public sequencerUptimeFeeds;

    mapping(address => address) public dataFeeds;

    mapping(bytes32 => mapping(address => uint256)) public backtrackTokenPrices;

    constructor(
        IAddressesProvider _addressProvider,
        address[] memory _assets,
        address[] memory _feeds
    ) Roleable(_addressProvider) {
        _setAssetPrices(_assets, _feeds);
        priceAge = 10;
    }

    modifier onlyTimelock() {
        require(msg.sender == ADDRESS_PROVIDER.timelock(), "only timelock");
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

    function decimals() public pure override returns (uint256) {
        return PRICE_DECIMALS;
    }

    function setTokenConfig(address[] memory assets, address[] memory feeds) external onlyTimelock {
        _setAssetPrices(assets, feeds);
    }

    function _setAssetPrices(address[] memory assets, address[] memory feeds) private {
        require(assets.length == feeds.length, "inconsistent params length");
        for (uint256 i = 0; i < assets.length; i++) {
            require(assets[i] != address(0), "!0");
            dataFeeds[assets[i]] = feeds[i];
            emit FeedUpdate(assets[i], feeds[i]);
        }
    }

    function getPrice(address token) public view override returns (uint256) {
        (, uint256 price,,,) = latestRoundData(token);
        return price;
    }

    function getPriceSafely(address token) external view override returns (uint256) {
        (, uint256 price,, uint256 updatedAt,) = latestRoundData(token);
        if (block.timestamp > updatedAt + priceAge) {
            revert("invalid price");
        }
        return price;
    }

    function updateHistoricalPrice(
        address[] calldata tokens,
        bytes[] calldata,
        uint64 roundId
    ) external payable onlyExecutor onlyBacktracking override {
        for (uint256 i = 0; i < tokens.length; i++) {
            (, uint256 price,,,) = getRoundData(tokens[i], uint80(roundId));
            address token = tokens[i];
            bytes32 backtrackRound = bytes32(abi.encodePacked(uint64(block.timestamp), roundId));
            backtrackTokenPrices[backtrackRound][token] = price;
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
        return backtrackTokenPrices[backtrackRound][token];
    }

    function latestRoundData(address token) public view returns (uint80 roundId, uint256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        address dataFeedAddress = dataFeeds[token];
        require(dataFeedAddress != address(0), "invalid data feed");

        if (sequencerUptimeFeeds[token] != address(0)) {
            checkSequencerStatus(token);
        }
        AggregatorV3Interface dataFeed = AggregatorV3Interface(dataFeedAddress);
        uint256 _decimals = uint256(dataFeed.decimals());
        int256 answer;
        (roundId, answer, startedAt, updatedAt, answeredInRound) = dataFeed.latestRoundData();
        require(answer > 0, "invalid price");
        price = uint256(answer) * (10 ** (PRICE_DECIMALS - _decimals));
    }

    function getRoundData(
        address token,
        uint80 _roundId
    ) public view returns (uint80 roundId, uint256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        address dataFeedAddress = dataFeeds[token];
        require(dataFeedAddress != address(0), "invalid data feed");

        if (sequencerUptimeFeeds[token] != address(0)) {
            checkSequencerStatus(token);
        }
        AggregatorV3Interface dataFeed = AggregatorV3Interface(dataFeedAddress);
        uint256 _decimals = uint256(dataFeed.decimals());
        int256 answer;
        (roundId, answer, startedAt, updatedAt, answeredInRound) = dataFeed.getRoundData(_roundId);
        require(answer > 0, "invalid price");
        price = uint256(answer) * (10 ** (PRICE_DECIMALS - _decimals));
    }

    function checkSequencerStatus(address token) public view {
        address sequencerAddress = sequencerUptimeFeeds[token];
        require(sequencerAddress != address(0), "invalid sequencer");

        AggregatorV3Interface sequencer = AggregatorV3Interface(sequencerAddress);
        (, int256 answer, uint256 startedAt,,) = sequencer.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert("SequencerDown");
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert("GracePeriodNotOver");
        }
    }
}
