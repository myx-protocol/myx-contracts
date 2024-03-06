// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPriceFeed {

    event PriceAgeUpdated(uint256 oldAge, uint256 newAge);

    function getPrice(address token) external view returns (uint256);

    function getPriceSafely(address token) external view returns (uint256);

    function decimals() external pure returns (uint256);

}
