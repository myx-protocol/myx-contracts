// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPool {
    // Events
    event PairAdded(
        address indexed indexToken,
        address indexed stableToken,
        address lpToken,
        uint256 index
    );

    event UpdateTotalAmount(
        uint256 indexed pairIndex,
        int256 indexAmount,
        int256 stableAmount,
        uint256 indexTotalAmount,
        uint256 stableTotalAmount
    );

    event UpdateReserveAmount(
        uint256 indexed pairIndex,
        int256 indexAmount,
        int256 stableAmount,
        uint256 indexReservedAmount,
        uint256 stableReservedAmount
    );

    event UpdateLPProfit(
        uint256 indexed pairIndex,
        address token,
        int256 profit,
        uint256 totalAmount
    );

    event UpdateAveragePrice(uint256 indexed pairIndex, uint256 averagePrice);

    event UpdateSpotSwap(address sender, address oldAddress, address newAddress);

    event UpdatePoolView(address sender, address oldAddress, address newAddress);

    event UpdateRouter(address sender, address oldAddress, address newAddress);

    event UpdateRiskReserve(address sender, address oldAddress, address newAddress);

    event UpdateFeeCollector(address sender, address oldAddress, address newAddress);

    event UpdatePositionManager(address sender, address oldAddress, address newAddress);

    event UpdateOrderManager(address sender, address oldAddress, address newAddress);

    event AddStableToken(address sender, address token);

    event RemoveStableToken(address sender, address token);

    event AddLiquidity(
        address indexed recipient,
        uint256 indexed pairIndex,
        uint256 indexAmount,
        uint256 stableAmount,
        uint256 lpAmount,
        uint256 indexFeeAmount,
        uint256 stableFeeAmount,
        address slipToken,
        uint256 slipFeeAmount,
        uint256 lpPrice
    );

    event RemoveLiquidity(
        address indexed recipient,
        uint256 indexed pairIndex,
        uint256 indexAmount,
        uint256 stableAmount,
        uint256 lpAmount,
        uint256 feeAmount,
        uint256 lpPrice
    );

    event ClaimedFee(address sender, address token, uint256 amount);

    struct Vault {
        uint256 indexTotalAmount; // total amount of tokens
        uint256 indexReservedAmount; // amount of tokens reserved for open positions
        uint256 stableTotalAmount;
        uint256 stableReservedAmount;
        uint256 averagePrice;
    }

    struct Pair {
        uint256 pairIndex;
        address indexToken;
        address stableToken;
        address pairToken;
        bool enable;
        uint256 kOfSwap; //Initial k value of liquidity
        uint256 expectIndexTokenP; //   for 100%
        uint256 maxUnbalancedP;
        uint256 unbalancedDiscountRate;
        uint256 addLpFeeP; // Add liquidity fee
        uint256 removeLpFeeP; // remove liquidity fee
    }

    struct TradingConfig {
        uint256 minLeverage;
        uint256 maxLeverage;
        uint256 minTradeAmount;
        uint256 maxTradeAmount;
        uint256 maxPositionAmount;
        uint256 maintainMarginRate; // Maintain the margin rate of  for 100%
        uint256 priceSlipP; // Price slip point
        uint256 maxPriceDeviationP; // Maximum offset of index price
    }

    struct TradingFeeConfig {
        uint256 lpFeeDistributeP;
        uint256 stakingFeeDistributeP;
        uint256 keeperFeeDistributeP;
        uint256 treasuryFeeDistributeP;
        uint256 reservedFeeDistributeP;
        uint256 ecoFundFeeDistributeP;
    }

    function pairsIndex() external view returns (uint256);

    function getPairIndex(address indexToken, address stableToken) external view returns (uint256);

    function getPair(uint256) external view returns (Pair memory);

    function getTradingConfig(uint256 _pairIndex) external view returns (TradingConfig memory);

    function getTradingFeeConfig(uint256) external view returns (TradingFeeConfig memory);

    function getVault(uint256 _pairIndex) external view returns (Vault memory vault);

    function transferTokenTo(address token, address to, uint256 amount) external;

    function transferEthTo(address to, uint256 amount) external;

    function transferTokenOrSwap(
        uint256 pairIndex,
        address token,
        address to,
        uint256 amount
    ) external;

    function increaseReserveAmount(
        uint256 _pairToken,
        uint256 _indexAmount,
        uint256 _stableAmount
    ) external;

    function decreaseReserveAmount(
        uint256 _pairToken,
        uint256 _indexAmount,
        uint256 _stableAmount
    ) external;

    function updateAveragePrice(uint256 _pairIndex, uint256 _averagePrice) external;

    function setLPStableProfit(uint256 _pairIndex, int256 _profit) external;

    function addLiquidity(
        address recipient,
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount,
        bytes calldata data
    ) external returns (uint256 mintAmount, address slipToken, uint256 slipAmount);

    function removeLiquidity(
        address payable _receiver,
        uint256 _pairIndex,
        uint256 _amount,
        bool useETH,
        bytes calldata data
    )
        external
        returns (uint256 receivedIndexAmount, uint256 receivedStableAmount, uint256 feeAmount);

    function claimFee(address token, uint256 amount) external;
}
