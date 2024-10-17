// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IConfigurationProvider.sol";
import "../libraries/Upgradeable.sol";
import "../libraries/Int256Utils.sol";

contract ConfigurationProvider is IConfigurationProvider, Upgradeable {
    using Int256Utils for int256;

    address public gov;

    mapping(uint256 => uint256) public baseFundingRateMaximum;

    mapping(uint256 => int256) public override baseFundingRate;

    function initialize(
        IAddressesProvider addressProvider,
        address _gov
    ) public initializer {
        ADDRESS_PROVIDER = addressProvider;
        gov = _gov;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "onlyGov");
        _;
    }

    function setGov(address _gov) external onlyPoolAdmin {
        address old = gov;
        gov = _gov;
        emit UpdateGovAddress(msg.sender, old, _gov);
    }

    function setBaseFundingRateMaximum(
        uint256[] memory _pairIndexes,
        uint256[] memory _baseFundingRateMaximums
    ) external onlyPoolAdmin {
        require(_pairIndexes.length == _baseFundingRateMaximums.length, "inconsistent params length");

        for (uint256 i = 0; i < _pairIndexes.length; i++) {
            baseFundingRateMaximum[_pairIndexes[i]] = _baseFundingRateMaximums[i];
            emit UpdateBaseFundingRateMaximum(msg.sender, _pairIndexes[i], _baseFundingRateMaximums[i]);
        }
    }

    function updateBaseFundingRate(
        uint256[] memory _pairIndexes,
        int256[] memory _baseFundingRates
    ) external onlyGov {
        require(_pairIndexes.length == _baseFundingRates.length, "inconsistent params length");

        for (uint256 i = 0; i < _pairIndexes.length; i++) {
            require(_baseFundingRates[i].abs() <= baseFundingRateMaximum[_pairIndexes[i]], "exceeds maximum");

            baseFundingRate[_pairIndexes[i]] = _baseFundingRates[i];
            emit UpdateBaseFundingRate(msg.sender, _pairIndexes[i], _baseFundingRates[i]);
        }
    }

}
