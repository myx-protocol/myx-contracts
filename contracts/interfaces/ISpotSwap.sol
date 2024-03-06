// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPool.sol";

interface ISpotSwap {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external ;

    function getSwapData(
        IPool.Pair memory pair,
        address _tokenOut,
        uint256 _expectAmountOut
    ) external view returns (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
}
