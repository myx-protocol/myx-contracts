// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../libraries/PrecisionUtils.sol";
import "../libraries/Upgradeable.sol";
import "../interfaces/IFeeCollector.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/IPool.sol";
import "../libraries/TradingTypes.sol";

contract FeeCollector is IFeeCollector, ReentrancyGuardUpgradeable, Upgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using PrecisionUtils for uint256;

    // Trading fee of each tier (pairIndex => tier => fee)
    mapping(uint256 => mapping(uint8 => TradingFeeTier)) public tradingFeeTiers;

    // Maximum of referrals ratio
    uint256 public override maxReferralsRatio;

    uint256 public override stakingTradingFee;
    // user + keeper
    mapping(address => uint256) public override userTradingFee;

    uint256 public override treasuryFee;

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
        uint256 claimableStakingTradingFee = stakingTradingFee;
        if (claimableStakingTradingFee > 0) {
            stakingTradingFee = 0;
            pool.transferTokenTo(pledgeAddress, msg.sender, claimableStakingTradingFee);
        }
        emit ClaimedStakingTradingFee(msg.sender, pledgeAddress, claimableStakingTradingFee);
        return claimableStakingTradingFee;
    }

    function claimTreasuryFee() external override onlyTreasury returns (uint256) {
        uint256 claimableTreasuryFee = treasuryFee;
        if (claimableTreasuryFee > 0) {
            treasuryFee = 0;
            pool.transferTokenTo(pledgeAddress, msg.sender, claimableTreasuryFee);
        }
        emit ClaimedDistributorTradingFee(msg.sender, pledgeAddress, claimableTreasuryFee);
        return claimableTreasuryFee;
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
        address keeper,
        uint256 sizeDelta,
        uint256 tradingFee,
        uint256 vipFeeRate,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner
    ) external override onlyPositionManagerOrLogic returns (uint256 lpAmount, uint256 vipDiscountAmount) {
        IPool.TradingFeeConfig memory tradingFeeConfig = pool.getTradingFeeConfig(pair.pairIndex);

        // vip discount
        uint256 vipTradingFee = sizeDelta.mulPercentage(vipFeeRate);
        vipDiscountAmount = tradingFee > vipTradingFee ? tradingFee - vipTradingFee : 0;
        userTradingFee[account] += vipDiscountAmount;

        uint256 surplusFee = tradingFee - vipDiscountAmount;

        // referrals amount
        uint256 referralsAmount;
        uint256 referralUserAmount;
        if (referralOwner != address(0)) {
            referralsAmount = surplusFee.mulPercentage(
                Math.min(referralsRatio, maxReferralsRatio)
            );
            referralUserAmount = surplusFee.mulPercentage(
                Math.min(Math.min(referralUserRatio, referralsRatio), maxReferralsRatio)
            );
            userTradingFee[account] += referralUserAmount;
            referralFee[referralOwner] += referralsAmount - referralUserAmount;

            surplusFee = surplusFee - referralsAmount;
        }

        lpAmount = surplusFee.mulPercentage(tradingFeeConfig.lpFeeDistributeP);
        pool.setLPStableProfit(pair.pairIndex, int256(lpAmount));

        uint256 keeperAmount = surplusFee.mulPercentage(tradingFeeConfig.keeperFeeDistributeP);
        userTradingFee[keeper] += keeperAmount;

        uint256 stakingAmount = surplusFee.mulPercentage(tradingFeeConfig.stakingFeeDistributeP);
        stakingTradingFee += stakingAmount;

        uint256 distributorAmount = surplusFee -
            lpAmount -
            keeperAmount -
            stakingAmount;
        treasuryFee += distributorAmount;

        emit DistributeTradingFee(
            account,
            pair.pairIndex,
            sizeDelta,
            tradingFee,
            vipDiscountAmount,
            vipFeeRate,
            referralsAmount,
            referralUserAmount,
            referralOwner,
            lpAmount,
            keeperAmount,
            stakingAmount,
            distributorAmount
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

    function _updateTradingFeeTier(
        uint256 pairIndex,
        uint8 tier,
        TradingFeeTier memory tierFee
    ) internal {
        TradingFeeTier memory regularTierFee = tradingFeeTiers[pairIndex][0];
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
}
