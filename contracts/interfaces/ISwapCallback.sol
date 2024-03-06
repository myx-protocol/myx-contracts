// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ISwapCallback {
    function swapCallback(
        address indexToken,
        address stableToken,
        uint256 indexAmount,
        uint256 stableAmount,
        bytes calldata data
    ) external;
}
