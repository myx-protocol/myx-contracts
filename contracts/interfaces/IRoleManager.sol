// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IRoleManager {
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

    function isAdmin(address) external view returns (bool);

    function isPoolAdmin(address poolAdmin) external view returns (bool);

    function isOperator(address operator) external view returns (bool);

    function isTreasurer(address treasurer) external view returns (bool);

    function isKeeper(address) external view returns (bool);

    function isBlackList(address account) external view returns (bool);
}
