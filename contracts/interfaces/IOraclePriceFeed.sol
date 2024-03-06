// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPriceFeed} from "./IPriceFeed.sol";

interface IOraclePriceFeed is IPriceFeed {

    function updateHistoricalPrice(
        address[] calldata tokens,
        bytes[] calldata updateData,
        uint64 backtrackRound
    ) external payable;

    function removeHistoricalPrice(
        uint64 backtrackRound,
        address[] calldata tokens
    ) external;

    function getHistoricalPrice(
        uint64 backtrackRound,
        address token
    ) external view returns (uint256);

}
