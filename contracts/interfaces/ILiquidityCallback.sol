// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface ILiquidityCallback {
    function addLiquidityCallback(
        address indexToken,
        address stableToken,
        uint256 amountIndex,
        uint256 amountStable,
        bytes calldata data
    ) external;

    function removeLiquidityCallback(address poolToken, uint256 amount, bytes calldata data) external;
}
