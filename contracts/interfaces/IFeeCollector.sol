// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPool.sol";
import "../libraries/TradingTypes.sol";

interface IFeeCollector {

    event UpdatedTradingFeeTier(
        address sender,
        uint8 tier,
        uint256 oldTakerFee,
        uint256 oldMakerFee,
        uint256 newTakerFee,
        uint256 newMakerFee
    );

    event UpdateMaxReferralsRatio(uint256 oldRatio, uint256 newRatio);

    event UpdatedStakingPoolAddress(address sender, address oldAddress, address newAddress);

    event UpdatedPositionManagerAddress(address sender, address oldAddress, address newAddress);

    event UpdateExecutionLogicAddress(address sender, address oldAddress, address newAddress);

    event DistributeTradingFee(
        address account,
        uint256 pairIndex,
        uint256 sizeDelta,
        uint256 tradingFee,
        uint256 vipDiscountAmount,
        uint256 vipFeeRate,
        uint256 referralsAmount,
        uint256 referralUserAmount,
        address referralOwner,
        uint256 lpAmount,
        uint256 keeperAmount,
        uint256 stakingAmount,
        uint256 distributorAmount
    );

    event ClaimedStakingTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedDistributorTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedReferralsTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedUserTradingFee(address account, address claimToken, uint256 amount);

    event ClaimedKeeperNetworkFee(address account, address claimToken, uint256 amount);

    struct TradingFeeTier {
        uint256 makerFee;
        uint256 takerFee;
    }

    function maxReferralsRatio() external view returns (uint256 maxReferenceRatio);

    function stakingTradingFee() external view returns (uint256);

    function treasuryFee() external view returns (uint256);

    function userTradingFee(address _account) external view returns (uint256);

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

    function claimKeeperNetworkFee(
        TradingTypes.InnerPaymentType paymentType
    ) external returns (uint256);

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
    ) external returns (uint256 lpAmount, uint256 vipDiscountAmount);

    function distributeNetworkFee(
        address keeper,
        TradingTypes.InnerPaymentType paymentType,
        uint256 networkFeeAmount
    ) external;
}
