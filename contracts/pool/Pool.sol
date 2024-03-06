// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IPositionManager.sol";
import "../interfaces/IUniSwapV3Router.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPoolToken.sol";
import "../interfaces/IPoolTokenFactory.sol";
import "../interfaces/ISwapCallback.sol";
import "../interfaces/IPythOraclePriceFeed.sol";
import "../interfaces/ISpotSwap.sol";
import "../interfaces/ILiquidityCallback.sol";
import "../interfaces/IWETH.sol";
import "../libraries/AmountMath.sol";
import "../libraries/Upgradeable.sol";
import "../libraries/Int256Utils.sol";
import "../libraries/AMMUtils.sol";
import "../libraries/PrecisionUtils.sol";
import "../token/interfaces/IBaseToken.sol";
import "../helpers/ValidationHelper.sol";
import "../helpers/TokenHelper.sol";
import "../interfaces/IPoolView.sol";

contract Pool is IPool, Upgradeable {
    using PrecisionUtils for uint256;
    using SafeERC20 for IERC20;
    using Int256Utils for int256;
    using Math for uint256;
    using SafeMath for uint256;

    IPoolTokenFactory public poolTokenFactory;
    IPoolView public poolView;

    address public riskReserve;
    address public feeCollector;

    mapping(uint256 => TradingConfig) public tradingConfigs;
    mapping(uint256 => TradingFeeConfig) public tradingFeeConfigs;

    mapping(address => mapping(address => uint256)) public override getPairIndex;

    uint256 public pairsIndex;
    mapping(uint256 => Pair) public pairs;
    mapping(uint256 => Vault) public vaults;
    address public positionManager;
    address public orderManager;
    address public router;

    mapping(address => uint256) public feeTokenAmounts;
    mapping(address => bool) public isStableToken;
    address public spotSwap;

    function initialize(
        IAddressesProvider addressProvider,
        IPoolTokenFactory _poolTokenFactory
    ) public initializer {
        ADDRESS_PROVIDER = addressProvider;
        poolTokenFactory = _poolTokenFactory;
        pairsIndex = 1;
    }

    modifier transferAllowed() {
        require(
            positionManager == msg.sender ||
                orderManager == msg.sender ||
                riskReserve == msg.sender ||
                feeCollector == msg.sender,
            "pd"
        );
        _;
    }

    receive() external payable {
        require(msg.sender == ADDRESS_PROVIDER.WETH() || msg.sender == orderManager, "nw");
    }

    modifier onlyPositionManager() {
        require(positionManager == msg.sender, "opm");
        _;
    }

    modifier onlyRouter() {
        require(router == msg.sender, "or");
        _;
    }

    modifier onlyPositionManagerOrFeeCollector() {
        require(
            positionManager == msg.sender || msg.sender == feeCollector,
            "opmof"
        );
        _;
    }

    modifier onlyTreasury() {
        require(
            IRoleManager(ADDRESS_PROVIDER.roleManager()).isTreasurer(msg.sender),
            "ot"
        );
        _;
    }

    function _unwrapWETH(uint256 amount, address payable to) private {
        IWETH(ADDRESS_PROVIDER.WETH()).withdraw(amount);
        (bool success, ) = to.call{value: amount}(new bytes(0));
        require(success, "err-eth");
    }

    function setPoolView(address _poolView) external onlyPoolAdmin {
        address oldAddress = address(poolView);
        poolView = IPoolView(_poolView);
        emit UpdatePoolView(msg.sender, oldAddress, _poolView);
    }

    function setSpotSwap(address _spotSwap) external onlyPoolAdmin {
        address oldAddress = spotSwap;
        spotSwap = _spotSwap;
        emit UpdateSpotSwap(msg.sender, oldAddress, _spotSwap);
    }

    function setRiskReserve(address _riskReserve) external onlyPoolAdmin {
        address oldAddress = riskReserve;
        riskReserve = _riskReserve;
        emit UpdateRiskReserve(msg.sender, oldAddress, _riskReserve);
    }

    function setFeeCollector(address _feeCollector) external onlyPoolAdmin {
        address oldAddress = feeCollector;
        feeCollector = _feeCollector;
        emit UpdateFeeCollector(msg.sender, oldAddress, _feeCollector);
    }

    function setPositionManager(address _positionManager) external onlyPoolAdmin {
        address oldAddress = positionManager;
        positionManager = _positionManager;
        emit UpdatePositionManager(msg.sender, oldAddress, _positionManager);
    }

    function setOrderManager(address _orderManager) external onlyPoolAdmin {
        address oldAddress = orderManager;
        orderManager = _orderManager;
        emit UpdateOrderManager(msg.sender, oldAddress, _orderManager);
    }

    function setRouter(address _router) external onlyPoolAdmin {
        address oldAddress = router;
        router = _router;
        emit UpdateRouter(msg.sender, oldAddress, _router);
    }

    function addStableToken(address _token) external onlyPoolAdmin {
        isStableToken[_token] = true;
        emit AddStableToken(msg.sender, _token);
    }

    function removeStableToken(address _token) external onlyPoolAdmin {
        delete isStableToken[_token];
        emit RemoveStableToken(msg.sender, _token);
    }

    function addPair(address _indexToken, address _stableToken) external onlyPoolAdmin {
        require(_indexToken != address(0) && _stableToken != address(0), "!0");
        require(isStableToken[_stableToken], "!st");
        require(getPairIndex[_indexToken][_stableToken] == 0, "ex");
        require(IERC20Metadata(_indexToken).decimals() <= 18 && IERC20Metadata(_stableToken).decimals() <= 18, "!de");

        address pairToken = poolTokenFactory.createPoolToken(_indexToken, _stableToken);

        getPairIndex[_indexToken][_stableToken] = pairsIndex;
        getPairIndex[_stableToken][_indexToken] = pairsIndex;

        Pair storage pair = pairs[pairsIndex];
        pair.pairIndex = pairsIndex;
        pair.indexToken = _indexToken;

        pair.stableToken = _stableToken;
        pair.pairToken = pairToken;

        emit PairAdded(_indexToken, _stableToken, pairToken, pairsIndex++);
    }

    function updatePair(uint256 _pairIndex, Pair calldata _pair) external onlyPoolAdmin {
        Pair storage pair = pairs[_pairIndex];
        require(
            pair.indexToken != address(0) && pair.stableToken != address(0),
            "nex"
        );
        require(
            _pair.expectIndexTokenP <= PrecisionUtils.percentage() &&
                _pair.maxUnbalancedP <= PrecisionUtils.percentage() &&
                _pair.unbalancedDiscountRate <= PrecisionUtils.percentage() &&
                _pair.addLpFeeP <= PrecisionUtils.percentage() &&
                _pair.removeLpFeeP <= PrecisionUtils.percentage(),
            "ex"
        );

        pair.enable = _pair.enable;
        pair.kOfSwap = _pair.kOfSwap;
        pair.expectIndexTokenP = _pair.expectIndexTokenP;
        pair.maxUnbalancedP = _pair.maxUnbalancedP;
        pair.unbalancedDiscountRate = _pair.unbalancedDiscountRate;
        pair.addLpFeeP = _pair.addLpFeeP;
        pair.removeLpFeeP = _pair.removeLpFeeP;
    }

    function updateTradingConfig(
        uint256 _pairIndex,
        TradingConfig calldata _tradingConfig
    ) external onlyPoolAdmin {
        Pair storage pair = pairs[_pairIndex];
        require(
            pair.indexToken != address(0) && pair.stableToken != address(0),
            "pnt"
        );
        require(
            _tradingConfig.maintainMarginRate <= PrecisionUtils.percentage() &&
                _tradingConfig.priceSlipP <= PrecisionUtils.percentage() &&
                _tradingConfig.maxPriceDeviationP <= PrecisionUtils.percentage(),
            "ex"
        );
        tradingConfigs[_pairIndex] = _tradingConfig;
    }

    function updateTradingFeeConfig(
        uint256 _pairIndex,
        TradingFeeConfig calldata _tradingFeeConfig
    ) external onlyPoolAdmin {
        Pair storage pair = pairs[_pairIndex];
        require(
            pair.indexToken != address(0) && pair.stableToken != address(0),
            "pne"
        );
        require(
            _tradingFeeConfig.lpFeeDistributeP +
                _tradingFeeConfig.keeperFeeDistributeP +
                _tradingFeeConfig.stakingFeeDistributeP +
                _tradingFeeConfig.treasuryFeeDistributeP +
                _tradingFeeConfig.reservedFeeDistributeP +
                _tradingFeeConfig.ecoFundFeeDistributeP <=
                PrecisionUtils.percentage(),
            "ex"
        );
        tradingFeeConfigs[_pairIndex] = _tradingFeeConfig;
    }

    function _increaseTotalAmount(
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount
    ) internal {
        Vault storage vault = vaults[_pairIndex];
        vault.indexTotalAmount = vault.indexTotalAmount + _indexAmount;
        vault.stableTotalAmount = vault.stableTotalAmount + _stableAmount;
        emit UpdateTotalAmount(
            _pairIndex,
            int256(_indexAmount),
            int256(_stableAmount),
            vault.indexTotalAmount,
            vault.stableTotalAmount
        );
    }

    function _decreaseTotalAmount(
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount
    ) internal {
        Vault storage vault = vaults[_pairIndex];
        require(vault.indexTotalAmount >= _indexAmount, "ix");
        require(vault.stableTotalAmount >= _stableAmount, "ix");

        vault.indexTotalAmount = vault.indexTotalAmount - _indexAmount;
        vault.stableTotalAmount = vault.stableTotalAmount - _stableAmount;
        emit UpdateTotalAmount(
            _pairIndex,
            -int256(_indexAmount),
            -int256(_stableAmount),
            vault.indexTotalAmount,
            vault.stableTotalAmount
        );
    }

    function increaseReserveAmount(
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount
    ) external onlyPositionManager {
        Vault storage vault = vaults[_pairIndex];
        vault.indexReservedAmount = vault.indexReservedAmount + _indexAmount;
        vault.stableReservedAmount = vault.stableReservedAmount + _stableAmount;
        emit UpdateReserveAmount(
            _pairIndex,
            int256(_indexAmount),
            int256(_stableAmount),
            vault.indexReservedAmount,
            vault.stableReservedAmount
        );
    }

    function decreaseReserveAmount(
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount
    ) external onlyPositionManager {
        Vault storage vault = vaults[_pairIndex];
        require(vault.indexReservedAmount >= _indexAmount, "ex");
        require(vault.stableReservedAmount >= _stableAmount, "ex");

        vault.indexReservedAmount = vault.indexReservedAmount - _indexAmount;
        vault.stableReservedAmount = vault.stableReservedAmount - _stableAmount;
        emit UpdateReserveAmount(
            _pairIndex,
            -int256(_indexAmount),
            -int256(_stableAmount),
            vault.indexReservedAmount,
            vault.stableReservedAmount
        );
    }

    function updateAveragePrice(
        uint256 _pairIndex,
        uint256 _averagePrice
    ) external onlyPositionManager {
        vaults[_pairIndex].averagePrice = _averagePrice;
        emit UpdateAveragePrice(_pairIndex, _averagePrice);
    }

    function setLPStableProfit(
        uint256 _pairIndex,
        int256 _profit
    ) external onlyPositionManagerOrFeeCollector {
        Vault storage vault = vaults[_pairIndex];
        Pair memory pair = pairs[_pairIndex];
        if (_profit > 0) {
            vault.stableTotalAmount += _profit.abs();
        } else {
            if (vault.stableTotalAmount < _profit.abs()) {
                _swapInUni(_pairIndex, pair.stableToken, _profit.abs());
            }
            vault.stableTotalAmount -= _profit.abs();
        }

        emit UpdateLPProfit(_pairIndex, pair.stableToken, _profit, vault.stableTotalAmount);
    }

    function addLiquidity(
        address recipient,
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount,
        bytes calldata data
    ) external onlyRouter returns (uint256 mintAmount, address slipToken, uint256 slipAmount) {
        ValidationHelper.validateAccountBlacklist(ADDRESS_PROVIDER, recipient);

        Pair memory pair = pairs[_pairIndex];
        require(pair.enable, "disabled");

        return _addLiquidity(recipient, _pairIndex, _indexAmount, _stableAmount, data);
    }

    function removeLiquidity(
        address payable _receiver,
        uint256 _pairIndex,
        uint256 _amount,
        bool useETH,
        bytes calldata data
    ) external onlyRouter returns (uint256 receivedIndexAmount, uint256 receivedStableAmount, uint256 feeAmount) {
        ValidationHelper.validateAccountBlacklist(ADDRESS_PROVIDER, _receiver);

        Pair memory pair = pairs[_pairIndex];
        require(pair.enable, "disabled");

        (receivedIndexAmount, receivedStableAmount, feeAmount) = _removeLiquidity(
            _receiver,
            _pairIndex,
            _amount,
            useETH,
            data
        );

        return (receivedIndexAmount, receivedStableAmount, feeAmount);
    }

    function _transferToken(
        address indexToken,
        address stableToken,
        uint256 indexAmount,
        uint256 stableAmount,
        bytes calldata data
    ) internal {
        uint256 balanceIndexBefore;
        uint256 balanceStableBefore;
        if (indexAmount > 0) balanceIndexBefore = IERC20(indexToken).balanceOf(address(this));
        if (stableAmount > 0) balanceStableBefore = IERC20(stableToken).balanceOf(address(this));
        ILiquidityCallback(msg.sender).addLiquidityCallback(
            indexToken,
            stableToken,
            indexAmount,
            stableAmount,
            data
        );

        if (indexAmount > 0)
            require(
                balanceIndexBefore.add(indexAmount) <= IERC20(indexToken).balanceOf(address(this)),
                "ti"
            );
        if (stableAmount > 0) {
            require(
                balanceStableBefore.add(stableAmount) <=
                    IERC20(stableToken).balanceOf(address(this)),
                "ts"
            );
        }
    }

    function _swapInUni(uint256 _pairIndex, address _tokenOut, uint256 _expectAmountOut) private {
        Pair memory pair = pairs[_pairIndex];
        (
            address tokenIn,
            address tokenOut,
            uint256 amountInMaximum,
            uint256 expectAmountOut
        ) = ISpotSwap(spotSwap).getSwapData(pair, _tokenOut, _expectAmountOut);

        if (IERC20(tokenIn).allowance(address(this), spotSwap) < amountInMaximum) {
            IERC20(tokenIn).safeApprove(spotSwap, type(uint256).max);
        }
        ISpotSwap(spotSwap).swap(tokenIn, tokenOut, amountInMaximum, expectAmountOut);
    }

    function _getStableTotalAmount(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) internal view returns (uint256) {
        int256 profit = getProfit(pair.pairIndex, pair.stableToken, price);
        if (profit < 0) {
            return vault.stableTotalAmount > profit.abs() ? vault.stableTotalAmount.sub(profit.abs()) : 0;
        } else {
            return vault.stableTotalAmount.add(profit.abs());
        }
    }

    function _getIndexTotalAmount(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) internal view returns (uint256) {
        int256 profit = getProfit(pair.pairIndex, pair.indexToken, price);
        if (profit < 0) {
            return vault.indexTotalAmount > profit.abs() ? vault.indexTotalAmount.sub(profit.abs()) : 0;
        } else {
            return vault.indexTotalAmount.add(profit.abs());
        }
    }

    function _addLiquidity(
        address recipient,
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount,
        bytes calldata data
    ) private returns (uint256 mintAmount, address slipToken, uint256 slipAmount) {
        require(_indexAmount > 0 || _stableAmount > 0, "ia");

        IPool.Pair memory pair = getPair(_pairIndex);
        require(pair.pairToken != address(0), "ip");

        _transferToken(pair.indexToken, pair.stableToken, _indexAmount, _stableAmount, data);

        uint256 price = IPythOraclePriceFeed(ADDRESS_PROVIDER.priceOracle()).getPriceSafely(pair.indexToken);
        uint256 lpPrice = poolView.lpFairPrice(_pairIndex, price);

        uint256 indexFeeAmount;
        uint256 stableFeeAmount;
        uint256 afterFeeIndexAmount;
        uint256 afterFeeStableAmount;
        (
            mintAmount,
            slipToken,
            slipAmount,
            indexFeeAmount,
            stableFeeAmount,
            afterFeeIndexAmount,
            afterFeeStableAmount
        ) = poolView.getMintLpAmount(_pairIndex, _indexAmount, _stableAmount, price);

        feeTokenAmounts[pair.indexToken] += indexFeeAmount;
        feeTokenAmounts[pair.stableToken] += stableFeeAmount;

        if (slipToken == pair.indexToken) {
            afterFeeIndexAmount += slipAmount;
        } else if (slipToken == pair.stableToken) {
            afterFeeStableAmount += slipAmount;
        }
        _increaseTotalAmount(_pairIndex, afterFeeIndexAmount, afterFeeStableAmount);

        IBaseToken(pair.pairToken).mint(recipient, mintAmount);

        emit AddLiquidity(
            recipient,
            _pairIndex,
            _indexAmount,
            _stableAmount,
            mintAmount,
            indexFeeAmount,
            stableFeeAmount,
            slipToken,
            slipAmount,
            lpPrice
        );

        return (mintAmount, slipToken, slipAmount);
    }

    function _removeLiquidity(
        address payable _receiver,
        uint256 _pairIndex,
        uint256 _amount,
        bool useETH,
        bytes calldata data
    )
        private
        returns (
            uint256 receiveIndexTokenAmount,
            uint256 receiveStableTokenAmount,
            uint256 feeAmount
        )
    {
        require(_amount > 0, "ia");
        IPool.Pair memory pair = getPair(_pairIndex);
        require(pair.pairToken != address(0), "ip");

        uint256 price = IPythOraclePriceFeed(ADDRESS_PROVIDER.priceOracle()).getPriceSafely(pair.indexToken);
        uint256 lpPrice = poolView.lpFairPrice(_pairIndex, price);

        uint256 feeIndexTokenAmount;
        uint256 feeStableTokenAmount;
        (
            receiveIndexTokenAmount,
            receiveStableTokenAmount,
            feeAmount,
            feeIndexTokenAmount,
            feeStableTokenAmount
        ) = poolView.getReceivedAmount(_pairIndex, _amount, price);

        ILiquidityCallback(msg.sender).removeLiquidityCallback(pair.pairToken, _amount, data);
        IPoolToken(pair.pairToken).burn(_amount);

        IPool.Vault memory vault = getVault(_pairIndex);
        uint256 indexTokenDec = IERC20Metadata(pair.indexToken).decimals();
        uint256 stableTokenDec = IERC20Metadata(pair.stableToken).decimals();

        uint256 availableIndexTokenWad;
        if (vault.indexTotalAmount > vault.indexReservedAmount) {
            uint256 availableIndexToken = vault.indexTotalAmount - vault.indexReservedAmount;
            availableIndexTokenWad = availableIndexToken * (10 ** (18 - indexTokenDec));
        }

        uint256 availableStableTokenWad;
        if (vault.stableTotalAmount > vault.stableReservedAmount) {
            uint256 availableStableToken = vault.stableTotalAmount - vault.stableReservedAmount;
            availableStableTokenWad = availableStableToken * (10 ** (18 - stableTokenDec));
        }

        uint256 receiveIndexTokenAmountWad = receiveIndexTokenAmount * (10 ** (18 - indexTokenDec));
        uint256 receiveStableTokenAmountWad = receiveStableTokenAmount * (10 ** (18 - stableTokenDec));

        uint256 totalAvailable = availableIndexTokenWad.mulPrice(price) + availableStableTokenWad;
        uint256 totalReceive = receiveIndexTokenAmountWad.mulPrice(price) + receiveStableTokenAmountWad;
        require(totalReceive <= totalAvailable, "il");

        feeTokenAmounts[pair.indexToken] += feeIndexTokenAmount;
        feeTokenAmounts[pair.stableToken] += feeStableTokenAmount;

        _decreaseTotalAmount(
            _pairIndex,
            receiveIndexTokenAmount + feeIndexTokenAmount,
            receiveStableTokenAmount + feeStableTokenAmount
        );

        if (receiveIndexTokenAmount > 0) {
            if (useETH && pair.indexToken == ADDRESS_PROVIDER.WETH()) {
                _unwrapWETH(receiveIndexTokenAmount, _receiver);
            } else {
                IERC20(pair.indexToken).safeTransfer(_receiver, receiveIndexTokenAmount);
            }
        }

        if (receiveStableTokenAmount > 0) {
            IERC20(pair.stableToken).safeTransfer(_receiver, receiveStableTokenAmount);
        }

        emit RemoveLiquidity(
            _receiver,
            _pairIndex,
            receiveIndexTokenAmount,
            receiveStableTokenAmount,
            _amount,
            feeAmount,
            lpPrice
        );

        return (receiveIndexTokenAmount, receiveStableTokenAmount, feeAmount);
    }

    function claimFee(address token, uint256 amount) external onlyTreasury {
        require(feeTokenAmounts[token] >= amount, "ex");

        feeTokenAmounts[token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit ClaimedFee(msg.sender, token, amount);
    }

    function transferTokenTo(address token, address to, uint256 amount) external transferAllowed {
        require(IERC20(token).balanceOf(address(this)) > amount, "Insufficient balance");
        IERC20(token).safeTransfer(to, amount);
    }

    function transferEthTo(address to, uint256 amount) external transferAllowed {
        require(address(this).balance > amount, "Insufficient balance");
        (bool success, ) = to.call{value: amount}(new bytes(0));
        require(success, "transfer failed");
    }

    function transferTokenOrSwap(
        uint256 pairIndex,
        address token,
        address to,
        uint256 amount
    ) external transferAllowed {
        if (amount == 0) {
            return;
        }
        Pair memory pair = pairs[pairIndex];
        require(token == pair.indexToken || token == pair.stableToken, "bt");

        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal < amount) {
            _swapInUni(pairIndex, token, amount);
        }
        IERC20(token).safeTransfer(to, amount);
    }

    function getProfit(uint pairIndex, address token, uint256 price) private view returns (int256 profit) {
        return IPositionManager(positionManager).lpProfit(pairIndex, token, price);
    }

    function getVault(uint256 _pairIndex) public view returns (Vault memory vault) {
        return vaults[_pairIndex];
    }

    function getPair(uint256 _pairIndex) public view override returns (Pair memory) {
        return pairs[_pairIndex];
    }

    function getTradingConfig(
        uint256 _pairIndex
    ) external view override returns (TradingConfig memory) {
        return tradingConfigs[_pairIndex];
    }

    function getTradingFeeConfig(
        uint256 _pairIndex
    ) external view override returns (TradingFeeConfig memory) {
        return tradingFeeConfigs[_pairIndex];
    }
}
