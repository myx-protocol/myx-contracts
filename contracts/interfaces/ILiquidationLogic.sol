// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IExecution.sol";

interface ILiquidationLogic is IExecution {

    event ExecuteLiquidation(
        bytes32 positionKey,
        address account,
        uint256 pairIndex,
        bool isLong,
        uint256 collateral,
        uint256 sizeAmount,
        uint256 price,
        uint256 orderId
    );

    event UpdateExecutorAddress(address sender, address oldAddress, address newAddress);

    function updateExecutor(address _executor) external;

    function liquidationPosition(
        address keeper,
        bytes32 positionKey,
        uint8 tier,
        uint256 referralsRatio,
        uint256 referralUserRatio,
        address referralOwner
    ) external;

    function cleanInvalidPositionOrders(
        bytes32[] calldata positionKeys
    ) external;
}
