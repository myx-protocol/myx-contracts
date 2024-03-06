// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {PositionStatus, IPositionManager} from "../interfaces/IPositionManager.sol";
import "../libraries/Position.sol";
import "../libraries/PositionKey.sol";
import "../libraries/PrecisionUtils.sol";
import "../libraries/Int256Utils.sol";
import "../interfaces/IFundingRate.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";
import "../interfaces/IRiskReserve.sol";
import "../interfaces/IFeeCollector.sol";
import "../libraries/Upgradeable.sol";
import "../helpers/TokenHelper.sol";

contract TradingHelperMock {
    IPool public pool;

    constructor(address _pool) {
        pool = IPool(_pool);
    }

    function convertIndexAmountToStable(
        uint256 pairIndex,
        int256 indexTokenAmount
    ) external view returns (int256 amount) {
        IPool.Pair memory pair = pool.getPair(pairIndex);
        return TokenHelper.convertIndexAmountToStable(pair, indexTokenAmount);
    }
}
