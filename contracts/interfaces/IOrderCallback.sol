// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IOrderCallback {
    function createOrderCallback(address collateral, uint256 amount, address to, bytes calldata data) external;
}
