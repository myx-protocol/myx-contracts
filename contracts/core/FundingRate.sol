// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IFundingRate.sol";
import "../interfaces/IConfigurationProvider.sol";
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

    mapping(uint256 => FundingFeeConfigV2) public fundingFeeConfigsV2;

    address public configurationProvider;

    function initialize(IAddressesProvider addressProvider) public initializer {
        ADDRESS_PROVIDER = addressProvider;
    }

    function updateConfigurationProviderAddress(
        address _configurationProvider
    ) external onlyPoolAdmin {
        address old = configurationProvider;
        configurationProvider = _configurationProvider;
        emit UpdateConfigurationProviderAddress(msg.sender, old, _configurationProvider);
    }

    function updateFundingFeeConfig(
        uint256 _pairIndex,
        FundingFeeConfig calldata _fundingFeeConfig
    ) external onlyPoolAdmin {
        revert("deprecated");
    }

    function updateFundingFeeConfigV2(
        uint256 _pairIndex,
        FundingFeeConfigV2 calldata _fundingFeeConfig
    ) external onlyPoolAdmin {
        require(
            _fundingFeeConfig.growthRateLow.abs() <= PrecisionUtils.percentage() &&
            _fundingFeeConfig.growthRateHigh.abs() <= PrecisionUtils.percentage() &&
            _fundingFeeConfig.range <= PrecisionUtils.percentage() &&
            _fundingFeeConfig.maxRate.abs() <= PrecisionUtils.percentage() &&
            _fundingFeeConfig.fundingInterval <= 86400,
            "exceed max"
        );

        fundingFeeConfigsV2[_pairIndex] = _fundingFeeConfig;
    }

    function getFundingInterval(uint256 _pairIndex) public view override returns (uint256) {
        FundingFeeConfigV2 memory fundingFeeConfig = fundingFeeConfigsV2[_pairIndex];
        return fundingFeeConfig.fundingInterval;
    }

    function getFundingRate(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) public view override returns (int256 fundingRate) {
        revert("deprecated");
    }

    function getFundingRateV2(
        IPool pool,
        uint256 pairIndex,
        uint256 price
    ) public view override returns (int256 fundingRate) {
        FundingFeeConfigV2 memory fundingFeeConfig = fundingFeeConfigsV2[pairIndex];

        int256 baseRate = IConfigurationProvider(configurationProvider).baseFundingRate(pairIndex);
        int256 maxRate = fundingFeeConfig.maxRate;
        uint256 range = fundingFeeConfig.range;

        (int256 v, int256 u,) = pool.getAvailableLiquidity(pairIndex, price);

        int256 precision = int256(PrecisionUtils.fundingRatePrecision());
        int256 g1 = baseRate;
        if (u + v != 0) {
            int256 r = (u - v) * precision / (u + v);
            int256 k = r.abs() <= range ? fundingFeeConfig.growthRateLow : fundingFeeConfig.growthRateHigh;

            int256 rSq = (r * r) / 2 / precision;
            int256 adjustment = (rSq * k) / precision;

            if (r >= 0) {
                g1 = Int256Utils.min(adjustment + baseRate, maxRate);
            } else {
                g1 = Int256Utils.max(baseRate - adjustment, -maxRate);
            }
        }

        fundingRate = g1 / int256(86400 / fundingFeeConfig.fundingInterval);
    }
}
