// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IRiskReserve {

    event UpdatedDaoAddress(
        address sender,
        address oldAddress,
        address newAddress
    );

    event UpdatedPositionManagerAddress(
        address sender,
        address oldAddress,
        address newAddress
    );

    event UpdatedPoolAddress(
        address sender,
        address oldAddress,
        address newAddress
    );

    event Withdraw(
        address sender,
        address asset,
        uint256 amount,
        address to
    );

    function updateDaoAddress(address newAddress) external;

    function updatePositionManagerAddress(address newAddress) external;

    function updatePoolAddress(address newAddress) external;

    function increase(address asset, uint256 amount) external;

    function decrease(address asset, uint256 amount) external;

    function recharge(address asset, uint256 amount) external;

    function withdraw(address asset, address to, uint256 amount) external;
}
