// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IConfigurationProvider {

    event UpdateGovAddress(address sender, address oldAddress, address newAddress);

    event UpdateBaseFundingRateMaximum(address sender, uint256 pairIndex, uint256 maxBaseFundingRate);

    event UpdateBaseFundingRate(address sender, uint256 pairIndex, int256 baseFundingRate);

    function baseFundingRate(uint256 pairIndex) external view returns (int256);

    function baseFundingRateMaximum(uint256 pairIndex) external view returns (uint256);
}
