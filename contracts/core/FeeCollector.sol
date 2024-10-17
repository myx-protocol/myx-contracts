// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../libraries/PrecisionUtils.sol";
import "../libraries/Upgradeable.sol";
import "../libraries/Int256Utils.sol";
import "../interfaces/IFeeCollector.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/IPool.sol";
import "../libraries/TradingTypes.sol";
import "../helpers/TokenHelper.sol";

contract FeeCollector is IFeeCollector, ReentrancyGuardUpgradeable, Upgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Int256Utils for int256;
    using PrecisionUtils for uint256;

    // Trading fee of each tier (pairIndex => tier => fee)
    mapping(uint256 => mapping(uint8 => TradingFeeTier)) public tradingFeeTiers;

    // Maximum of referrals ratio
    uint256 public override maxReferralsRatio;

    uint256 public override stakingTradingFee;

    uint256 public override stakingTradingFeeDebt;

    mapping(address => uint256) public override userTradingFee;

    mapping(address => int256) public override keeperTradingFee;

    uint256 public override treasuryFee;

    uint256 public override treasuryFeeDebt;

    int256 public override reservedTradingFee;

    int256 public override ecoFundTradingFee;

    mapping(address => uint256) public override referralFee;

    mapping(address => mapping(TradingTypes.InnerPaymentType => uint256)) public keeperNetworkFee;

    address public pledgeAddress;

    address public addressStakingPool;
    address public addressPositionManager;
    address public addressExecutionLogic;
    IPool public pool;

    function initialize(
        IAddressesProvider addressesProvider,
        IPool _pool,
        address _pledgeAddress
    ) public initializer {
        ADDRESS_PROVIDER = addressesProvider;
        pool = _pool;
        pledgeAddress = _pledgeAddress;
        maxReferralsRatio = 0.5e8;
    }

    modifier onlyPositionManagerOrLogic() {
        require(msg.sender == addressPositionManager || msg.sender == addressExecutionLogic, "onlyPositionManager");
        _;
    }

    modifier onlyTreasury() {
        require(IRoleManager(ADDRESS_PROVIDER.roleManager()).isTreasurer(msg.sender), "onlyTreasury");
        _;
    }

    modifier onlyStakingPool() {
        require(msg.sender == addressStakingPool, "onlyStakingPool");
        _;
    }

    function getTradingFeeTier(uint256 pairIndex, uint8 tier) external view override returns (TradingFeeTier memory) {
        return tradingFeeTiers[pairIndex][tier];
    }

    function getRegularTradingFeeTier(uint256 pairIndex) external view override returns (TradingFeeTier memory) {
        return tradingFeeTiers[pairIndex][0];
    }

    function getKeeperNetworkFee(
        address account,
        TradingTypes.InnerPaymentType paymentType
    ) external view override returns (uint256) {
        return keeperNetworkFee[account][paymentType];
    }

    function updatePositionManagerAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = addressPositionManager;
        addressPositionManager = newAddress;

        emit UpdatedPositionManagerAddress(msg.sender, oldAddress, newAddress);
    }

    function updateExecutionLogicAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = addressExecutionLogic;
        addressExecutionLogic = newAddress;

        emit UpdateExecutionLogicAddress(msg.sender, oldAddress, newAddress);
    }

    function updateStakingPoolAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = addressStakingPool;
        addressStakingPool = newAddress;

        emit UpdatedStakingPoolAddress(msg.sender, oldAddress, newAddress);
    }

    function updatePoolAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = address(pool);
        pool = IPool(newAddress);

        emit UpdatePoolAddress(msg.sender, oldAddress, newAddress);
    }

    function updatePledgeAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = pledgeAddress;
        pledgeAddress = newAddress;

        emit UpdatePledgeAddress(msg.sender, oldAddress, newAddress);
    }

    function updateTradingFeeTiers(
        uint256 pairIndex,
        uint8[] memory tiers,
        TradingFeeTier[] memory tierFees
    ) external onlyPoolAdmin {
        require(tiers.length == tierFees.length, "inconsistent params length");

        for (uint256 i = 0; i < tiers.length; i++) {
            _updateTradingFeeTier(pairIndex, tiers[i], tierFees[i]);
        }
    }

    function updateTradingFeeTier(
        uint256 pairIndex,
        uint8 tier,
        TradingFeeTier memory tierFee
    ) external onlyPoolAdmin {
        _updateTradingFeeTier(pairIndex, tier, tierFee);
    }

    function updateMaxReferralsRatio(uint256 newRatio) external override onlyPoolAdmin {
        require(newRatio <= PrecisionUtils.percentage(), "exceeds max ratio");

        uint256 oldRatio = maxReferralsRatio;
        maxReferralsRatio = newRatio;

        emit UpdateMaxReferralsRatio(oldRatio, newRatio);
    }

    function claimStakingTradingFee() external override onlyStakingPool returns (uint256) {
        require(stakingTradingFee > stakingTradingFeeDebt, "insufficient available balance");

        uint256 claimableStakingTradingFee = stakingTradingFee - stakingTradingFeeDebt;
        stakingTradingFee = 0;
        stakingTradingFeeDebt = 0;
        pool.transferTokenTo(pledgeAddress, msg.sender, claimableStakingTradingFee);

        emit ClaimedStakingTradingFee(msg.sender, pledgeAddress, claimableStakingTradingFee);
        return claimableStakingTradingFee;
    }

    function claimTreasuryFee() external override onlyTreasury returns (uint256) {
        require(treasuryFee > treasuryFeeDebt, "insufficient available balance");

        uint256 claimableTreasuryFee = treasuryFee - treasuryFeeDebt;
        treasuryFee = 0;
        treasuryFeeDebt = 0;
        pool.transferTokenTo(pledgeAddress, msg.sender, claimableTreasuryFee);

        emit ClaimedDistributorTradingFee(msg.sender, pledgeAddress, claimableTreasuryFee);
        return claimableTreasuryFee;
    }

    function claimReservedTradingFee() external onlyTreasury returns (uint256) {
        require(reservedTradingFee > 0, "insufficient available balance");

        uint256 claimableReservedTradingFee = reservedTradingFee.abs();
        reservedTradingFee = 0;
        pool.transferTokenTo(pledgeAddress, msg.sender, claimableReservedTradingFee);
        emit ClaimedReservedTradingFee(msg.sender, pledgeAddress, claimableReservedTradingFee);
        return claimableReservedTradingFee;
    }

    function claimEcoFundTradingFee() external onlyTreasury returns (uint256) {
        require(ecoFundTradingFee > 0, "insufficient available balance");

        uint256 claimableEcoFundTradingFee = ecoFundTradingFee.abs();
        ecoFundTradingFee = 0;
        pool.transferTokenTo(pledgeAddress, msg.sender, claimableEcoFundTradingFee);
        emit ClaimedEcoFundTradingFee(msg.sender, pledgeAddress, claimableEcoFundTradingFee);
        return claimableEcoFundTradingFee;
    }

    function claimReferralFee() external override nonReentrant returns (uint256) {
        uint256 claimableReferralFee = referralFee[msg.sender];
        if (claimableReferralFee > 0) {
            referralFee[msg.sender] = 0;
            pool.transferTokenTo(pledgeAddress, msg.sender, claimableReferralFee);
        }
        emit ClaimedReferralsTradingFee(msg.sender, pledgeAddress, claimableReferralFee);
        return claimableReferralFee;
    }

    function claimUserTradingFee() external override nonReentrant returns (uint256) {
        uint256 claimableUserTradingFee = userTradingFee[msg.sender];
        if (claimableUserTradingFee > 0) {
            userTradingFee[msg.sender] = 0;
            pool.transferTokenTo(pledgeAddress, msg.sender, claimableUserTradingFee);
        }
        emit ClaimedUserTradingFee(msg.sender, pledgeAddress, claimableUserTradingFee);
        return claimableUserTradingFee;
    }

    function claimKeeperTradingFee() external override nonReentrant returns (uint256) {
        int256 claimableKeeperTradingFee = keeperTradingFee[msg.sender];

        require(claimableKeeperTradingFee > 0, "insufficient available balance");
        keeperTradingFee[msg.sender] = 0;
        pool.transferTokenTo(pledgeAddress, msg.sender, uint256(claimableKeeperTradingFee));

        emit ClaimedKeeperTradingFee(msg.sender, pledgeAddress, uint256(claimableKeeperTradingFee));
        return uint256(claimableKeeperTradingFee);
    }

    function claimKeeperNetworkFee(
        TradingTypes.InnerPaymentType paymentType
    ) external override nonReentrant returns (uint256) {
        uint256 claimableNetworkFee = keeperNetworkFee[msg.sender][paymentType];
        address claimableToken = address(0);
        if (claimableNetworkFee > 0) {
            keeperNetworkFee[msg.sender][paymentType] = 0;
            if (paymentType == TradingTypes.InnerPaymentType.ETH) {
                pool.transferEthTo(msg.sender, claimableNetworkFee);
            } else if (paymentType == TradingTypes.InnerPaymentType.COLLATERAL) {
                claimableToken = pledgeAddress;
                pool.transferTokenTo(pledgeAddress, msg.sender, claimableNetworkFee);
            }
        }
        emit ClaimedKeeperNetworkFee(msg.sender, claimableToken, claimableNetworkFee);
        return claimableNetworkFee;
    }

    function distributeTradingFee(
        IPool.Pair memory pair,
        address account,
        uint256 orderId,
        address keeper,
        uint256 size,
        uint256 sizeDelta,
        uint256 executionPrice,
        uint256 tradingFee,
        bool isMaker,
        TradingFeeTier memory tradingFeeTier,
        int256 exposureAmount,
        int256 afterExposureAmount,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner
    ) external override onlyPositionManagerOrLogic returns (int256 lpAmount, int256 vipTradingFee, uint256 givebackFeeAmount) {
        IPool.TradingFeeConfig memory tradingFeeConfig = pool.getTradingFeeConfig(pair.pairIndex);
        uint256 avgPrice = pool.getVault(pair.pairIndex).averagePrice;
        // vip discount

        // negative maker rate
        if (isMaker && tradingFeeTier.makerFee < 0 && exposureAmount != 0) {
            int256 offset;
            if (exposureAmount < 0) {
                uint256 diffRatio = executionPrice * PrecisionUtils.percentage() / avgPrice;
                offset = SignedMath.min(0, int256(diffRatio) - int256(PrecisionUtils.percentage()));
            } else {
                uint256 diffRatio = avgPrice * PrecisionUtils.percentage() / executionPrice;
                offset = SignedMath.min(0, int256(diffRatio) - int256(PrecisionUtils.percentage()));
            }

            int256 feeRate = afterExposureAmount.abs() < exposureAmount.abs() ? tradingFeeTier.makerFee : int256(0);
            uint256 rebateAmount = uint256(
                TokenHelper.convertIndexAmountToStableWithPrice(pair, int256(size), avgPrice)
            ) * uint256(SignedMath.max(0, int256(feeRate.abs()) + offset)) / PrecisionUtils.percentage();

            (
                uint256 lpReturnAmount,
                uint256 keeperReturnAmount,
                uint256 stakingReturnAmount,
                uint256 reservedReturnAmount,
                uint256 ecoFundReturnAmount,
                uint256 treasuryReturnAmount
            ) = _collectTradingFee(pair.pairIndex, rebateAmount, tradingFeeConfig, keeper);

            givebackFeeAmount += tradingFee + rebateAmount;
            userTradingFee[account] += givebackFeeAmount;

            emit DistributeTradingFeeV2(
                account,
                pair.pairIndex,
                orderId,
                sizeDelta,
                tradingFee,
                isMaker,
                feeRate,
                -int256(rebateAmount),
                givebackFeeAmount,
                0,
                0,
                address(0),
                -int256(lpReturnAmount),
                -int256(keeperReturnAmount),
                -int256(stakingReturnAmount),
                -int256(reservedReturnAmount),
                -int256(ecoFundReturnAmount),
                -int256(treasuryReturnAmount)
            );
            return (-int256(lpReturnAmount), -int256(rebateAmount), givebackFeeAmount);
        }

        uint256 vipFeeRate = isMaker ? uint256(tradingFeeTier.makerFee) : tradingFeeTier.takerFee;
        vipTradingFee = int256(sizeDelta.mulPercentage(vipFeeRate));

        givebackFeeAmount = tradingFee > uint256(vipTradingFee) ? tradingFee - uint256(vipTradingFee) : 0;
        userTradingFee[account] += givebackFeeAmount;

        uint256 surplusFee = tradingFee - givebackFeeAmount;

        // referrals amount
        uint256 referralsAmount;
        uint256 referralUserAmount;
        if (referralOwner != address(0)) {
            referralsAmount = surplusFee.mulPercentage(
                Math.min(referralsRatio, maxReferralsRatio)
            );
            referralUserAmount = surplusFee.mulPercentage(Math.min(referralUserRatio, referralsRatio));

            referralFee[account] += referralUserAmount;
            referralFee[referralOwner] += referralsAmount - referralUserAmount;

            surplusFee = surplusFee - referralsAmount;
        }

        lpAmount = int256(surplusFee.mulPercentage(tradingFeeConfig.lpFeeDistributeP));
        pool.setLPStableProfit(pair.pairIndex, lpAmount);

        uint256 keeperAmount = surplusFee.mulPercentage(tradingFeeConfig.keeperFeeDistributeP);
        keeperTradingFee[keeper] += int256(keeperAmount);

        uint256 stakingAmount = surplusFee.mulPercentage(tradingFeeConfig.stakingFeeDistributeP);
        stakingTradingFee += stakingAmount;

        uint256 reservedAmount = surplusFee.mulPercentage(tradingFeeConfig.reservedFeeDistributeP);
        reservedTradingFee += int256(reservedAmount);

        uint256 ecoFundAmount = surplusFee.mulPercentage(tradingFeeConfig.ecoFundFeeDistributeP);
        ecoFundTradingFee += int256(ecoFundAmount);

        uint256 distributorAmount = surplusFee - uint256(lpAmount) - keeperAmount - stakingAmount - reservedAmount - ecoFundAmount;
        treasuryFee += distributorAmount;

        emit DistributeTradingFeeV2(
            account,
            pair.pairIndex,
            orderId,
            sizeDelta,
            tradingFee,
            isMaker,
            int256(vipFeeRate),
            vipTradingFee,
            givebackFeeAmount,
            referralsAmount,
            referralUserAmount,
            referralOwner,
            lpAmount,
            int256(keeperAmount),
            int256(stakingAmount),
            int256(reservedAmount),
            int256(ecoFundAmount),
            int256(distributorAmount)
        );
    }

    function distributeNetworkFee(
        address keeper,
        TradingTypes.InnerPaymentType paymentType,
        uint256 networkFeeAmount
    ) external override onlyPositionManagerOrLogic {
        if (paymentType != TradingTypes.InnerPaymentType.NONE) {
            keeperNetworkFee[keeper][paymentType] += networkFeeAmount;
        }
    }

    function _collectTradingFee(
        uint256 pairIndex,
        uint256 amount,
        IPool.TradingFeeConfig memory tradingFeeConfig,
        address keeper
    ) internal returns (
        uint256 lpReturnAmount,
        uint256 keeperReturnAmount,
        uint256 stakingReturnAmount,
        uint256 reservedReturnAmount,
        uint256 ecoFundReturnAmount,
        uint256 treasuryReturnAmount
    ){
        if (amount == 0) {
            return (0, 0, 0, 0, 0, 0);
        }
        lpReturnAmount = amount.mulPercentage(tradingFeeConfig.lpFeeDistributeP);
        pool.givebackTradingFee(pairIndex, lpReturnAmount);

        keeperReturnAmount = amount.mulPercentage(tradingFeeConfig.keeperFeeDistributeP);
        keeperTradingFee[keeper] -= int256(keeperReturnAmount);

        stakingReturnAmount = amount.mulPercentage(tradingFeeConfig.stakingFeeDistributeP);
        stakingTradingFeeDebt += stakingReturnAmount;

        reservedReturnAmount = amount.mulPercentage(tradingFeeConfig.reservedFeeDistributeP);
        reservedTradingFee -= int256(reservedReturnAmount);

        ecoFundReturnAmount = amount.mulPercentage(tradingFeeConfig.ecoFundFeeDistributeP);
        ecoFundTradingFee -= int256(ecoFundReturnAmount);

        treasuryReturnAmount = amount - (lpReturnAmount + keeperReturnAmount + stakingReturnAmount + reservedReturnAmount + ecoFundReturnAmount);
        treasuryFeeDebt += treasuryReturnAmount;
    }

    function _updateTradingFeeTier(
        uint256 pairIndex,
        uint8 tier,
        TradingFeeTier memory tierFee
    ) internal {
        TradingFeeTier memory regularTierFee = tradingFeeTiers[pairIndex][0];
        require(tier != 0 || tierFee.makerFee >= 0, "makerFee must be non-negative for tier 0");
        require(tier == 0
            || (tierFee.takerFee <= regularTierFee.takerFee && tierFee.makerFee <= regularTierFee.makerFee),
            "exceeds max ratio"
        );

        TradingFeeTier memory oldTierFee = tradingFeeTiers[pairIndex][tier];
        tradingFeeTiers[pairIndex][tier] = tierFee;

        emit UpdatedTradingFeeTier(
            msg.sender,
            tier,
            oldTierFee.takerFee,
            oldTierFee.makerFee,
            tradingFeeTiers[pairIndex][tier].takerFee,
            tradingFeeTiers[pairIndex][tier].makerFee
        );
    }

    function rescueKeeperNetworkFee(
        TradingTypes.InnerPaymentType paymentType,
        RescueKeeperNetworkFee[] calldata rescues
    ) external override nonReentrant onlyAdmin {
        for (uint256 i = 0; i < rescues.length; i++) {
            uint256 claimableNetworkFee = keeperNetworkFee[rescues[i].keeper][paymentType];
            address claimableToken = address(0);
            if (claimableNetworkFee > 0) {
                keeperNetworkFee[rescues[i].keeper][paymentType] = 0;
                if (paymentType == TradingTypes.InnerPaymentType.ETH) {
                    pool.transferEthTo(rescues[i].receiver, claimableNetworkFee);
                } else if (paymentType == TradingTypes.InnerPaymentType.COLLATERAL) {
                    claimableToken = pledgeAddress;
                    pool.transferTokenTo(pledgeAddress, rescues[i].receiver, claimableNetworkFee);
                }
            }
            emit ClaimedKeeperNetworkFee(rescues[i].keeper, claimableToken, claimableNetworkFee);
        }
    }

}
