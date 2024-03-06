// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/Math.sol';
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import '../libraries/PrecisionUtils.sol';
import '../libraries/Int256Utils.sol';
import '../libraries/TradingTypes.sol';
import '../libraries/PositionKey.sol';
import "../interfaces/IPool.sol";
import "../helpers/TokenHelper.sol";

library Position {
    using Int256Utils for int256;
    using Math for uint256;
    using PrecisionUtils for uint256;

    struct Info {
        address account;
        uint256 pairIndex;
        bool isLong;
        uint256 collateral;
        uint256 positionAmount;
        uint256 averagePrice;
        int256 fundingFeeTracker;
    }

    function get(
        mapping(bytes32 => Info) storage self,
        address _account,
        uint256 _pairIndex,
        bool _isLong
    ) internal view returns (Position.Info storage position) {
        position = self[PositionKey.getPositionKey(_account, _pairIndex, _isLong)];
    }

    function getPositionByKey(
        mapping(bytes32 => Info) storage self,
        bytes32 key
    ) internal view returns (Position.Info storage position) {
        position = self[key];
    }

    function init(Info storage self, uint256 pairIndex, address account, bool isLong, uint256 oraclePrice) internal {
        self.pairIndex = pairIndex;
        self.account = account;
        self.isLong = isLong;
        self.averagePrice = oraclePrice;
    }

    function getUnrealizedPnl(
        Info memory self,
        IPool.Pair memory pair,
        uint256 _sizeAmount,
        uint256 price
    ) internal view returns (int256 pnl) {
        if (price == self.averagePrice || self.averagePrice == 0 || _sizeAmount == 0) {
            return 0;
        }

        if (self.isLong) {
            if (price > self.averagePrice) {
                pnl = TokenHelper.convertIndexAmountToStableWithPrice(
                    pair,
                    int256(_sizeAmount),
                    price - self.averagePrice
                );
            } else {
                pnl = TokenHelper.convertIndexAmountToStableWithPrice(
                    pair,
                    -int256(_sizeAmount),
                    self.averagePrice - price
                );
            }
        } else {
            if (self.averagePrice > price) {
                pnl = TokenHelper.convertIndexAmountToStableWithPrice(
                    pair,
                    int256(_sizeAmount),
                    self.averagePrice - price
                );
            } else {
                pnl = TokenHelper.convertIndexAmountToStableWithPrice(
                    pair,
                    -int256(_sizeAmount),
                    price - self.averagePrice
                );
            }
        }

        return pnl;
    }

    function validLeverage(
        Info memory self,
        IPool.Pair memory pair,
        uint256 price,
        int256 _collateral,
        uint256 _sizeAmount,
        bool _increase,
        uint256 maxLeverage,
        uint256 maxPositionAmount,
        bool simpleVerify,
        int256 fundingFee
    ) internal view returns (uint256, uint256) {
        // only increase collateral
        if (_sizeAmount == 0 && _collateral >= 0) {
            return (self.positionAmount, self.collateral);
        }

        uint256 afterPosition;
        if (_increase) {
            afterPosition = self.positionAmount + _sizeAmount;
        } else {
            afterPosition = self.positionAmount >= _sizeAmount ? self.positionAmount - _sizeAmount : 0;
        }

        if (_increase && afterPosition > maxPositionAmount) {
            revert("exceeds max position");
        }

        int256 availableCollateral = int256(self.collateral) + fundingFee;

        // pnl
        if (!simpleVerify) {
            int256 pnl = getUnrealizedPnl(self, pair, self.positionAmount, price);
            if (!_increase && _sizeAmount > 0 && _sizeAmount < self.positionAmount) {
                if (pnl >= 0) {
                    availableCollateral += getUnrealizedPnl(self, pair, self.positionAmount - _sizeAmount, price);
                } else {
//                    availableCollateral += getUnrealizedPnl(self, pair, _sizeAmount, price);
                    availableCollateral += pnl;
                }
            } else {
                availableCollateral += pnl;
            }
        }

        // adjust collateral
        if (_collateral != 0) {
            availableCollateral += _collateral;
        }
        require(simpleVerify || availableCollateral >= 0, 'collateral not enough');

        if (!simpleVerify && ((_increase && _sizeAmount > 0) || _collateral < 0)) {
            uint256 collateralDec = uint256(IERC20Metadata(pair.stableToken).decimals());
            uint256 tokenDec = uint256(IERC20Metadata(pair.indexToken).decimals());

            uint256 tokenWad = 10 ** (PrecisionUtils.maxTokenDecimals() - tokenDec);
            uint256 collateralWad = 10 ** (PrecisionUtils.maxTokenDecimals() - collateralDec);

            uint256 afterPositionD = afterPosition * tokenWad;
            uint256 availableD = (availableCollateral.abs() * maxLeverage * collateralWad).divPrice(price);
            require(afterPositionD <= availableD, 'exceeds max leverage');
        }

        return (afterPosition, availableCollateral.abs());
    }
}
