// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

interface IPythOracle is IPyth {

    function latestPriceInfoPublishTime(
        bytes32 priceId
    ) external view returns (uint64);
}
