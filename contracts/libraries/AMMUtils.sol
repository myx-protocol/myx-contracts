// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";

library AMMUtils {
    function getReserve(
        uint256 k,
        uint256 price,
        uint256 pricePrecision
    ) internal pure returns (uint256 reserveA, uint256 reserveB) {
        require(price > 0, "Invalid price");
        require(k > 0, "Invalid k");

        reserveA = Math.sqrt(Math.mulDiv(k, pricePrecision, price));
        reserveB = k / reserveA;
        return (reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        require(reserveIn > 0 && reserveOut > 0, "Invalid reserve");
        amountOut = Math.mulDiv(amountIn, reserveOut, reserveIn + amountIn);
    }
}
