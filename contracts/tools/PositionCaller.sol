// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../libraries/Position.sol";
import "../interfaces/IFeeCollector.sol";
import "../interfaces/IPositionManager.sol";
import "../libraries/TradingTypes.sol";


contract PositionCaller {
    bytes32 private constant POSITION_MANAGER = "POSITION_MANAGER";
    bytes32 private constant FEE_COLLECTOR = "FEE_COLLECTOR";

    mapping(bytes32 => address) private _addresses;

    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    struct FundingFeeParam {
        address account;
        uint256 pairIndex;
        bool isLong;
    }

    struct TradingFeeParam{
        uint256 pairIndex;
        bool isLong;
        uint256 sizeAmount;
        uint256 price;
    }

    struct KeeperNetworkFeeParam{
        address account;
        TradingTypes.InnerPaymentType paymentType;
    }

    constructor( address _positionManager, address _feeCollector ){
        setAddress(POSITION_MANAGER, _positionManager);
        setAddress(FEE_COLLECTOR, _feeCollector);
    }

    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }

    function setAddress(bytes32 id, address newAddress) private {
        _addresses[id] = newAddress;
    }

    function getFundingFees(
        FundingFeeParam[] memory params
    ) public view returns (int256[] memory) {
        int256[] memory fundingFees = new int256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            FundingFeeParam memory fundingFeeParam = params[i];
            int256 fundingFee = IPositionManager(getAddress(POSITION_MANAGER)).getFundingFee(fundingFeeParam.account, fundingFeeParam.pairIndex, fundingFeeParam.isLong);
            fundingFees[i] = fundingFee;
        }
        return fundingFees;
    }

    function getTradingFees(
        TradingFeeParam[] memory params
    ) public view returns (uint256[] memory) {
        uint256[] memory tradingFees = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            TradingFeeParam memory tradingFeeParam = params[i];
            uint256 fundingFee = IPositionManager(getAddress(POSITION_MANAGER)).getTradingFee(tradingFeeParam.pairIndex, tradingFeeParam.isLong, tradingFeeParam.sizeAmount, tradingFeeParam.price);
            tradingFees[i] = fundingFee;
        }
        return tradingFees;
    }

    function getUserTradingFees(
        address[] memory params
    ) public view returns (uint256[] memory) {
        uint256[] memory vipRebates = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            uint256 vipRebate = IFeeCollector(getAddress(FEE_COLLECTOR)).userTradingFee(params[i]);
            vipRebates[i] = vipRebate;
        }
        return vipRebates;
    }

    function getReferralFees(
        address[] memory params
    ) public view returns (uint256[] memory) {
        uint256[] memory referralFees = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            uint256 referralFee = IFeeCollector(getAddress(FEE_COLLECTOR)).referralFee(params[i]);
            referralFees[i] = referralFee;
        }
        return referralFees;
    }

    function getKeeperNetworkFees(
        KeeperNetworkFeeParam[] memory params
    ) public view returns (uint256[] memory) {
        uint256[] memory networkFees = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            KeeperNetworkFeeParam memory networkFeeParam = params[i];
            uint256 networkFee = IFeeCollector(getAddress(FEE_COLLECTOR)).getKeeperNetworkFee(networkFeeParam.account, networkFeeParam.paymentType);
            networkFees[i] = networkFee;
        }
        return networkFees;
    }
}
