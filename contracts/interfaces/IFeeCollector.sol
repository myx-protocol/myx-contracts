// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPool.sol";
import "../libraries/TradingTypes.sol";
import "./IPositionManager.sol";

interface IFeeCollector {

    event UpdatedTradingFeeTier(
        address sender,
        uint8 tier,
        uint256 oldTakerFee,
        int256 oldMakerFee,
        uint256 newTakerFee,
        int256 newMakerFee
    );

    event UpdateMaxReferralsRatio(uint256 oldRatio, uint256 newRatio);

    event UpdatedStakingPoolAddress(address sender, address oldAddress, address newAddress);
    event UpdatePoolAddress(address sender, address oldAddress, address newAddress);
    event UpdatePledgeAddress(address sender, address oldAddress, address newAddress);

    event UpdatedPositionManagerAddress(address sender, address oldAddress, address newAddress);

    event UpdateExecutionLogicAddress(address sender, address oldAddress, address newAddress);

    event DistributeTradingFeeV2(
        address account,
        uint256 pairIndex,
        uint256 orderId,
        uint256 sizeDelta,
        uint256 regularTradingFee,
        bool isMaker,
        int256 feeRate,
        int256 vipTradingFee,
        uint256 returnAmount,
        uint256 referralsAmount,
        uint256 referralUserAmount,
        address referralOwner,
        int256 lpAmount,
        int256 keeperAmount,
        int256 stakingAmount,
        int256 reservedAmount,
        int256 ecoFundAmount,
        int256 treasuryAmount
    );

    event ClaimedStakingTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedDistributorTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedReservedTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedEcoFundTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedReferralsTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedUserTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedKeeperTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedKeeperNetworkFee(address account, address claimToken, uint256 amount);

    struct TradingFeeTier {
        int256 makerFee;
        uint256 takerFee;
    }

    function maxReferralsRatio() external view returns (uint256 maxReferenceRatio);

    function stakingTradingFee() external view returns (uint256);
    function stakingTradingFeeDebt() external view returns (uint256);

    function treasuryFee() external view returns (uint256);

    function treasuryFeeDebt() external view returns (uint256);

    function reservedTradingFee() external view returns (int256);

    function ecoFundTradingFee() external view returns (int256);

    function userTradingFee(address _account) external view returns (uint256);

    function keeperTradingFee(address _account) external view returns (int256);

    function referralFee(address _referralOwner) external view returns (uint256);

    function getTradingFeeTier(uint256 pairIndex, uint8 tier) external view returns (TradingFeeTier memory);

    function getRegularTradingFeeTier(uint256 pairIndex) external view returns (TradingFeeTier memory);

    function getKeeperNetworkFee(
        address account,
        TradingTypes.InnerPaymentType paymentType
    ) external view returns (uint256);

    function updateMaxReferralsRatio(uint256 newRatio) external;

    function claimStakingTradingFee() external returns (uint256);

    function claimTreasuryFee() external returns (uint256);

    function claimReferralFee() external returns (uint256);

    function claimUserTradingFee() external returns (uint256);

    function claimKeeperTradingFee() external returns (uint256);

    function claimKeeperNetworkFee(
        TradingTypes.InnerPaymentType paymentType
    ) external returns (uint256);

    struct RescueKeeperNetworkFee {
        address keeper;
        address receiver;
    }

    function rescueKeeperNetworkFee(
        TradingTypes.InnerPaymentType paymentType,
        RescueKeeperNetworkFee[] calldata rescues
    ) external;

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
    ) external returns (int256 lpAmount, int256 vipTradingFee, uint256 givebackFeeAmount);

    function distributeNetworkFee(
        address keeper,
        TradingTypes.InnerPaymentType paymentType,
        uint256 networkFeeAmount
    ) external;
}
