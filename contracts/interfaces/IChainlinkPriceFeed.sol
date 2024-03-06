// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IOraclePriceFeed.sol";

interface IChainlinkPriceFeed is IOraclePriceFeed {

    event FeedUpdate(address asset, address feed);

    event UpdatedExecutorAddress(address sender, address oldAddress, address newAddress);

}
