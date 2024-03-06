// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IFundingRate.sol";
import "../interfaces/IPool.sol";
import "../libraries/PrecisionUtils.sol";
import "../libraries/Upgradeable.sol";
import "../libraries/Int256Utils.sol";
import "../helpers/TokenHelper.sol";

contract FundingRate is IFundingRate, Upgradeable {
    using PrecisionUtils for uint256;
    using Int256Utils for int256;
    using Math for uint256;
    using SafeMath for uint256;

    mapping(uint256 => FundingFeeConfig) public fundingFeeConfigs;

    function initialize(IAddressesProvider addressProvider) public initializer {
        ADDRESS_PROVIDER = addressProvider;
    }

    function updateFundingFeeConfig(
        uint256 _pairIndex,
        FundingFeeConfig calldata _fundingFeeConfig
    ) external onlyPoolAdmin {
        require(
            _fundingFeeConfig.growthRate.abs() <= PrecisionUtils.percentage() &&
                _fundingFeeConfig.baseRate.abs() <= PrecisionUtils.percentage() &&
                _fundingFeeConfig.maxRate.abs() <= PrecisionUtils.percentage() &&
                _fundingFeeConfig.fundingInterval <= 86400,
            "exceed max"
        );

        fundingFeeConfigs[_pairIndex] = _fundingFeeConfig;
    }

    function getFundingInterval(uint256 _pairIndex) public view override returns (uint256) {
        FundingFeeConfig memory fundingFeeConfig = fundingFeeConfigs[_pairIndex];
        return fundingFeeConfig.fundingInterval;
    }

    function getFundingRate(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) public view override returns (int256 fundingRate) {
        FundingFeeConfig memory fundingFeeConfig = fundingFeeConfigs[pair.pairIndex];

        int256 baseRate = fundingFeeConfig.baseRate;
        int256 maxRate = fundingFeeConfig.maxRate;
        int256 k = fundingFeeConfig.growthRate;

        int256 u = int256(vault.stableTotalAmount)
            + TokenHelper.convertIndexAmountToStableWithPrice(pair, int256(vault.indexReservedAmount), price)
            - int256(vault.stableReservedAmount);
        int256 v = TokenHelper.convertIndexAmountToStableWithPrice(pair, int256(vault.indexTotalAmount), price)
            + int256(vault.stableReservedAmount)
            - TokenHelper.convertIndexAmountToStableWithPrice(pair, int256(vault.indexReservedAmount), price);

        if (u == v) {
            return baseRate / int256(86400 / fundingFeeConfig.fundingInterval);
        }

        int256 precision = int256(PrecisionUtils.fundingRatePrecision());
        // S = (U-V)/(U+V)
        int256 s = (u - v) * precision / (u + v);

        // G1 = MIN((S+S*S/2) * k + r, r(max))
        int256 g1 = _min(
            (((s * s) / 2 / precision) + s) * k / precision + baseRate,
            maxRate
        );
        fundingRate = g1 / int256(86400 / fundingFeeConfig.fundingInterval);
    }

    function _min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }
}
