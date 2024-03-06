// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

interface IMulticall {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}
