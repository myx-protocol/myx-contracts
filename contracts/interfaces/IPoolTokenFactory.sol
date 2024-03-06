// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IPoolTokenFactory {
    function createPoolToken(address indexToken, address stableToken) external returns (address);
}
