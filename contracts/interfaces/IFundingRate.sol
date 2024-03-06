// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPool.sol";

interface IFundingRate {
    struct FundingFeeConfig {
        int256 growthRate; // Growth rate base
        int256 baseRate; // Base interest rate
        int256 maxRate; // Maximum interest rate
        uint256 fundingInterval;
    }

    function getFundingInterval(uint256 _pairIndex) external view returns (uint256);

    function getFundingRate(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) external view returns (int256 fundingRate);
}
