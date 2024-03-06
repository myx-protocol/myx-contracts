// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPoolToken {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}
