// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IOraclePriceFeed.sol";

interface IPythOraclePriceFeed is IOraclePriceFeed {

    event TokenPriceIdUpdated(
        address token,
        bytes32 priceId
    );

    event PythAddressUpdated(address oldAddress, address newAddress);

    event UpdatedExecutorAddress(address sender, address oldAddress, address newAddress);

    event UnneededPricePublishWarn();

    function updatePrice(
        address[] calldata tokens,
        bytes[] calldata updateData,
        uint64[] calldata publishTimes
    ) external payable;
}
