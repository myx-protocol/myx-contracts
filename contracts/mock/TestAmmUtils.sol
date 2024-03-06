// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/AMMUtils.sol";

contract TestAmmUtils {

    constructor(){}

    function getReserve(
        uint256 k,
        uint256 price,
        uint256 pricePrecision
    ) external view returns (uint256 reserveA, uint256 reserveB) {
        return AMMUtils.getReserve(k, price, pricePrecision);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view returns (uint256 amountOut) {
        return AMMUtils.getAmountOut(amountIn, reserveIn, reserveOut);
    }
}
