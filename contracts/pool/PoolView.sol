// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IPositionManager.sol";
import "../interfaces/IPoolView.sol";
import "../libraries/AmountMath.sol";
import "../libraries/Upgradeable.sol";
import "../libraries/Int256Utils.sol";
import "../libraries/AMMUtils.sol";
import "../libraries/PrecisionUtils.sol";
import "../helpers/TokenHelper.sol";

contract PoolView is IPoolView, Upgradeable {
    using PrecisionUtils for uint256;
    using SafeERC20 for IERC20;
    using Int256Utils for int256;
    using Math for uint256;
    using SafeMath for uint256;

    IPool public pool;
    IPositionManager public positionManager;

    function initialize(
        IAddressesProvider addressProvider
    ) public initializer {
        ADDRESS_PROVIDER = addressProvider;
    }

    function setPool(address _pool) external onlyPoolAdmin {
        address oldAddress = address(pool);
        pool = IPool(_pool);
        emit UpdatePool(msg.sender, oldAddress, _pool);
    }

    function setPositionManager(address _positionManager) external onlyPoolAdmin {
        address oldAddress = address(positionManager);
        positionManager = IPositionManager(_positionManager);
        emit UpdatePositionManager(msg.sender, oldAddress, _positionManager);
    }

    function getMintLpAmount(
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount,
        uint256 price
    )
        external
        view
        override
        returns (
            uint256 mintAmount,
            address slipToken,
            uint256 slipAmount,
            uint256 indexFeeAmount,
            uint256 stableFeeAmount,
            uint256 afterFeeIndexAmount,
            uint256 afterFeeStableAmount
        )
    {
        if (_indexAmount == 0 && _stableAmount == 0) return (0, address(0), 0, 0, 0, 0, 0);
        require(price > 0, "ip");

        IPool.Pair memory pair = pool.getPair(_pairIndex);
        require(pair.pairToken != address(0), "ip");

        IPool.Vault memory vault = pool.getVault(_pairIndex);

        // transfer fee
        indexFeeAmount = _indexAmount.mulPercentage(pair.addLpFeeP);
        stableFeeAmount = _stableAmount.mulPercentage(pair.addLpFeeP);

        afterFeeIndexAmount = _indexAmount - indexFeeAmount;
        afterFeeStableAmount = _stableAmount - stableFeeAmount;

        uint256 indexTokenDec = IERC20Metadata(pair.indexToken).decimals();
        uint256 stableTokenDec = IERC20Metadata(pair.stableToken).decimals();

        uint256 indexTotalDeltaWad = uint256(TokenHelper.convertTokenAmountWithPrice(
            pair.indexToken, int256(_getIndexTotalAmount(pair, vault, price)), 18, price));
        uint256 stableTotalDeltaWad = uint256(TokenHelper.convertTokenAmountTo(
            pair.stableToken, int256(_getStableTotalAmount(pair, vault, price)), 18));

        uint256 indexDepositDeltaWad = uint256(TokenHelper.convertTokenAmountWithPrice(
            pair.indexToken, int256(afterFeeIndexAmount), 18, price));
        uint256 stableDepositDeltaWad = uint256(TokenHelper.convertTokenAmountTo(
            pair.stableToken, int256(afterFeeStableAmount), 18));

        uint256 slipDeltaWad;
        uint256 discountRate;
        uint256 discountAmount;
        if (indexTotalDeltaWad + stableTotalDeltaWad > 0) {
            // after deposit
            uint256 totalIndexTotalDeltaWad = indexTotalDeltaWad + indexDepositDeltaWad;
            uint256 totalStableTotalDeltaWad = stableTotalDeltaWad + stableDepositDeltaWad;

            // expect delta
            uint256 totalDelta = totalIndexTotalDeltaWad + totalStableTotalDeltaWad;
            uint256 expectIndexDeltaWad = totalDelta.mulPercentage(pair.expectIndexTokenP);
            uint256 expectStableDeltaWad = totalDelta - expectIndexDeltaWad;

            if (_indexAmount > 0 && _stableAmount == 0) {
                (discountRate, discountAmount) =
                    _getDiscount(pair, true, totalIndexTotalDeltaWad, expectIndexDeltaWad, totalDelta);
            }

            if (_stableAmount > 0 && _indexAmount == 0) {
                (discountRate, discountAmount) =
                    _getDiscount(pair, false, totalStableTotalDeltaWad, expectStableDeltaWad, totalDelta);
            }

            (uint256 reserveA, uint256 reserveB) = AMMUtils.getReserve(
                pair.kOfSwap,
                price,
                AmountMath.PRICE_PRECISION
            );
            if (totalIndexTotalDeltaWad > expectIndexDeltaWad) {
                uint256 needSwapIndexDeltaWad = totalIndexTotalDeltaWad - expectIndexDeltaWad;
                uint256 swapIndexDeltaWad = Math.min(indexDepositDeltaWad, needSwapIndexDeltaWad);

                slipDeltaWad = swapIndexDeltaWad
                    - AMMUtils.getAmountOut(
                        AmountMath.getIndexAmount(swapIndexDeltaWad, price),
                        reserveA,
                        reserveB
                    );
                slipAmount = AmountMath.getIndexAmount(slipDeltaWad, price) / (10 ** (18 - indexTokenDec));
                if (slipAmount > 0) {
                    slipToken = pair.indexToken;
                }

                afterFeeIndexAmount -= slipAmount;
            } else if (totalStableTotalDeltaWad > expectStableDeltaWad) {
                uint256 needSwapStableDeltaWad = totalStableTotalDeltaWad - expectStableDeltaWad;
                uint256 swapStableDeltaWad = Math.min(stableDepositDeltaWad, needSwapStableDeltaWad);

                slipDeltaWad = swapStableDeltaWad
                    - AMMUtils.getAmountOut(swapStableDeltaWad, reserveB, reserveA).mulPrice(price);
                slipAmount = slipDeltaWad / (10 ** (18 - stableTokenDec));
                if (slipAmount > 0) {
                    slipToken = pair.stableToken;
                }
                afterFeeStableAmount -= slipAmount;
            }
        }

        uint256 mintDeltaWad = indexDepositDeltaWad + stableDepositDeltaWad - slipDeltaWad;

        // mint with discount
        if (discountRate > 0) {
            if (mintDeltaWad > discountAmount) {
                mintAmount += AmountMath.getIndexAmount(
                    discountAmount,
                    lpFairPrice(_pairIndex, price).mulPercentage(
                        PrecisionUtils.percentage() - discountRate
                    )
                );
                mintDeltaWad -= discountAmount;
            } else {
                mintAmount += AmountMath.getIndexAmount(
                    mintDeltaWad,
                    lpFairPrice(_pairIndex, price).mulPercentage(
                        PrecisionUtils.percentage() - discountRate
                    )
                );
                mintDeltaWad = 0;
            }
        }

        if (mintDeltaWad > 0) {
            mintAmount += AmountMath.getIndexAmount(mintDeltaWad, lpFairPrice(_pairIndex, price));
        }

        return (
            mintAmount,
            slipToken,
            slipAmount,
            indexFeeAmount,
            stableFeeAmount,
            afterFeeIndexAmount,
            afterFeeStableAmount
        );
    }

    function lpFairPrice(uint256 _pairIndex, uint256 price) public view returns (uint256) {
        IPool.Pair memory pair = pool.getPair(_pairIndex);
        IPool.Vault memory vault = pool.getVault(_pairIndex);
        uint256 indexTokenDec = IERC20Metadata(pair.indexToken).decimals();
        uint256 stableTokenDec = IERC20Metadata(pair.stableToken).decimals();

        uint256 indexTotalAmountWad = _getIndexTotalAmount(pair, vault, price) * (10 ** (18 - indexTokenDec));
        uint256 stableTotalAmountWad = _getStableTotalAmount(pair, vault, price) * (10 ** (18 - stableTokenDec));

        uint256 lpFairDelta = AmountMath.getStableDelta(indexTotalAmountWad, price) + stableTotalAmountWad;

        return
            lpFairDelta > 0 && IERC20(pair.pairToken).totalSupply() > 0
                ? Math.mulDiv(
                    lpFairDelta,
                    AmountMath.PRICE_PRECISION,
                    IERC20(pair.pairToken).totalSupply()
                )
                : 1 * AmountMath.PRICE_PRECISION;
    }

    function getDepositAmount(
        uint256 _pairIndex,
        uint256 _lpAmount,
        uint256 price
    ) external view returns (uint256 depositIndexAmount, uint256 depositStableAmount) {
        if (_lpAmount == 0) return (0, 0);
        require(price > 0, "ipr");

        IPool.Pair memory pair = pool.getPair(_pairIndex);
        require(pair.pairToken != address(0), "ip");

        IPool.Vault memory vault = pool.getVault(_pairIndex);

        uint256 indexReserveDeltaWad = uint256(TokenHelper.convertTokenAmountWithPrice(
            pair.indexToken,
            int256(vault.indexTotalAmount),
            18,
            price
        ));
        uint256 stableReserveDeltaWad = uint256(TokenHelper.convertTokenAmountTo(
            pair.stableToken,
            int256(vault.stableTotalAmount),
            18
        ));
        uint256 depositDeltaWad = uint256(TokenHelper.convertTokenAmountWithPrice(
            pair.pairToken,
            int256(_lpAmount),
            18,
            lpFairPrice(_pairIndex, price)
        ));

        // expect delta
        uint256 totalDelta = (indexReserveDeltaWad + stableReserveDeltaWad + depositDeltaWad);
        uint256 expectIndexDelta = totalDelta.mulPercentage(pair.expectIndexTokenP);
        uint256 expectStableDelta = totalDelta - expectIndexDelta;

        uint256 depositIndexTokenDelta;
        uint256 depositStableTokenDelta;
        if (expectIndexDelta >= indexReserveDeltaWad) {
            uint256 extraIndexReserveDelta = expectIndexDelta - indexReserveDeltaWad;
            if (extraIndexReserveDelta >= depositDeltaWad) {
                depositIndexTokenDelta = depositDeltaWad;
            } else {
                depositIndexTokenDelta = extraIndexReserveDelta;
                depositStableTokenDelta = depositDeltaWad - extraIndexReserveDelta;
            }
        } else {
            uint256 extraStableReserveDelta = expectStableDelta - stableReserveDeltaWad;
            if (extraStableReserveDelta >= depositDeltaWad) {
                depositStableTokenDelta = depositDeltaWad;
            } else {
                depositIndexTokenDelta = depositDeltaWad - extraStableReserveDelta;
                depositStableTokenDelta = extraStableReserveDelta;
            }
        }
        uint256 indexTokenDec = uint256(IERC20Metadata(pair.indexToken).decimals());
        uint256 stableTokenDec = uint256(IERC20Metadata(pair.stableToken).decimals());

        depositIndexAmount = depositIndexTokenDelta * PrecisionUtils.pricePrecision() / price / (10 ** (18 - indexTokenDec));
        depositStableAmount = depositStableTokenDelta / (10 ** (18 - stableTokenDec));

        // add fee
        depositIndexAmount = depositIndexAmount.divPercentage(
            PrecisionUtils.percentage() - pair.addLpFeeP
        );
        depositStableAmount = depositStableAmount.divPercentage(
            PrecisionUtils.percentage() - pair.addLpFeeP
        );

        return (depositIndexAmount, depositStableAmount);
    }

    function getReceivedAmount(
        uint256 _pairIndex,
        uint256 _lpAmount,
        uint256 price
    ) external view returns (
            uint256 receiveIndexTokenAmount,
            uint256 receiveStableTokenAmount,
            uint256 feeAmount,
            uint256 feeIndexTokenAmount,
            uint256 feeStableTokenAmount
        )
    {
        if (_lpAmount == 0) return (0, 0, 0, 0, 0);
        require(price > 0, "ipr");

        IPool.Pair memory pair = pool.getPair(_pairIndex);
        require(pair.pairToken != address(0), "ip");

        IPool.Vault memory vault = pool.getVault(_pairIndex);

        uint256 indexTokenDec = IERC20Metadata(pair.indexToken).decimals();
        uint256 stableTokenDec = IERC20Metadata(pair.stableToken).decimals();

        uint256 indexReserveDeltaWad = uint256(TokenHelper.convertTokenAmountWithPrice(
            pair.indexToken,
            int256(vault.indexTotalAmount),
            18,
            price));
        uint256 stableReserveDeltaWad = uint256(TokenHelper.convertTokenAmountTo(
            pair.stableToken,
            int256(vault.stableTotalAmount),
            18));
        uint256 receiveDeltaWad = uint256(TokenHelper.convertTokenAmountWithPrice(
            pair.pairToken,
            int256(_lpAmount),
            18,
            lpFairPrice(_pairIndex, price)));

        require(indexReserveDeltaWad + stableReserveDeltaWad >= receiveDeltaWad, "insufficient liquidity");

        // expect delta
        uint256 totalDeltaWad = indexReserveDeltaWad + stableReserveDeltaWad - receiveDeltaWad;
        uint256 expectIndexDeltaWad = totalDeltaWad.mulPercentage(pair.expectIndexTokenP);
        uint256 expectStableDeltaWad = totalDeltaWad - expectIndexDeltaWad;

        // received delta of indexToken and stableToken
        uint256 receiveIndexTokenDeltaWad;
        uint256 receiveStableTokenDeltaWad;
        if (indexReserveDeltaWad > expectIndexDeltaWad) {
            uint256 extraIndexReserveDelta = indexReserveDeltaWad - expectIndexDeltaWad;
            if (extraIndexReserveDelta >= receiveDeltaWad) {
                receiveIndexTokenDeltaWad = receiveDeltaWad;
            } else {
                receiveIndexTokenDeltaWad = extraIndexReserveDelta;
                receiveStableTokenDeltaWad = receiveDeltaWad - extraIndexReserveDelta;
            }
        } else {
            uint256 extraStableReserveDelta = stableReserveDeltaWad - expectStableDeltaWad;
            if (extraStableReserveDelta >= receiveDeltaWad) {
                receiveStableTokenDeltaWad = receiveDeltaWad;
            } else {
                receiveIndexTokenDeltaWad = receiveDeltaWad - extraStableReserveDelta;
                receiveStableTokenDeltaWad = extraStableReserveDelta;
            }
        }
        receiveIndexTokenAmount = AmountMath.getIndexAmount(receiveIndexTokenDeltaWad, price) / (10 ** (18 - indexTokenDec));
        receiveStableTokenAmount = receiveStableTokenDeltaWad / (10 ** (18 - stableTokenDec));

        feeIndexTokenAmount = receiveIndexTokenAmount.mulPercentage(pair.removeLpFeeP);
        feeStableTokenAmount = receiveStableTokenAmount.mulPercentage(pair.removeLpFeeP);
        feeAmount = uint256(TokenHelper.convertIndexAmountToStableWithPrice(pair, int256(feeIndexTokenAmount), price)) + feeStableTokenAmount;

        receiveIndexTokenAmount -= feeIndexTokenAmount;
        receiveStableTokenAmount -= feeStableTokenAmount;

        uint256 availableIndexToken = vault.indexTotalAmount - vault.indexReservedAmount;
        uint256 availableStableToken = vault.stableTotalAmount - vault.stableReservedAmount;

        uint256 indexTokenAdd;
        uint256 stableTokenAdd;
        if (availableIndexToken < receiveIndexTokenAmount) {
            stableTokenAdd = uint256(TokenHelper.convertIndexAmountToStableWithPrice(
                pair,
                int256(receiveIndexTokenAmount - availableIndexToken),
                price));
            receiveIndexTokenAmount = availableIndexToken;
        }

        if (availableStableToken < receiveStableTokenAmount) {
            indexTokenAdd = uint256(TokenHelper.convertStableAmountToIndex(
                pair,
                int256(receiveStableTokenAmount - availableStableToken)
            )).divPrice(price);
            receiveStableTokenAmount = availableStableToken;
        }
        receiveIndexTokenAmount += indexTokenAdd;
        receiveStableTokenAmount += stableTokenAdd;

        return (
            receiveIndexTokenAmount,
            receiveStableTokenAmount,
            feeAmount,
            feeIndexTokenAmount,
            feeStableTokenAmount
        );
    }

    function _getDiscount(
        IPool.Pair memory pair,
        bool isIndex,
        uint256 delta,
        uint256 expectDelta,
        uint256 totalDelta
    ) internal pure returns (uint256 rate, uint256 amount) {
        uint256 ratio = delta.divPercentage(totalDelta);
        uint256 expectP = isIndex ? pair.expectIndexTokenP : PrecisionUtils.percentage().sub(pair.expectIndexTokenP);

        int256 unbalancedP = int256(ratio.divPercentage(expectP)) - int256(PrecisionUtils.percentage());
        if (unbalancedP < 0 && unbalancedP.abs() > pair.maxUnbalancedP) {
            rate = pair.unbalancedDiscountRate;
            amount = expectDelta.sub(delta);
        }
        return (rate, amount);
    }

    function _getStableTotalAmount(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) internal view returns (uint256) {
        int256 profit = positionManager.lpProfit(pair.pairIndex, pair.stableToken, price);
        if (profit < 0) {
            return vault.stableTotalAmount > profit.abs() ? vault.stableTotalAmount.sub(profit.abs()) : 0;
        } else {
            return vault.stableTotalAmount.add(profit.abs());
        }
    }

    function _getIndexTotalAmount(
        IPool.Pair memory pair,
        IPool.Vault memory vault,
        uint256 price
    ) internal view returns (uint256) {
        int256 profit = positionManager.lpProfit(pair.pairIndex, pair.indexToken, price);
        if (profit < 0) {
            return vault.indexTotalAmount > profit.abs() ? vault.indexTotalAmount.sub(profit.abs()) : 0;
        } else {
            return vault.indexTotalAmount.add(profit.abs());
        }
    }
}
