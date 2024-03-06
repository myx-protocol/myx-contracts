// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../libraries/PrecisionUtils.sol";
import "../interfaces/IPool.sol";

library TokenHelper {
    using PrecisionUtils for uint256;
    using SafeMath for uint256;

    function convertIndexAmountToStable(
        IPool.Pair memory pair,
        int256 indexTokenAmount
    ) internal view returns (int256 amount) {
        if (indexTokenAmount == 0) return 0;

        uint8 stableTokenDec = IERC20Metadata(pair.stableToken).decimals();
        return convertTokenAmountTo(pair.indexToken, indexTokenAmount, stableTokenDec);
    }

    function convertIndexAmountToStableWithPrice(
        IPool.Pair memory pair,
        int256 indexTokenAmount,
        uint256 price
    ) internal view returns (int256 amount) {
        if (indexTokenAmount == 0) return 0;

        uint8 stableTokenDec = IERC20Metadata(pair.stableToken).decimals();
        return convertTokenAmountWithPrice(pair.indexToken, indexTokenAmount, stableTokenDec, price);
    }

    function convertTokenAmountWithPrice(
        address token,
        int256 tokenAmount,
        uint8 targetDecimals,
        uint256 price
    ) internal view returns (int256 amount) {
        if (tokenAmount == 0) return 0;

        uint256 tokenDec = uint256(IERC20Metadata(token).decimals());

        uint256 tokenWad = 10 ** (PrecisionUtils.maxTokenDecimals() - tokenDec);
        uint256 targetTokenWad = 10 ** (PrecisionUtils.maxTokenDecimals() - targetDecimals);

        amount = (tokenAmount * int256(tokenWad)) * int256(price) / int256(targetTokenWad) / int256(PrecisionUtils.PRICE_PRECISION);
    }

    function convertStableAmountToIndex(
        IPool.Pair memory pair,
        int256 stableTokenAmount
    ) internal view returns (int256 amount) {
        if (stableTokenAmount == 0) return 0;

        uint8 indexTokenDec = IERC20Metadata(pair.indexToken).decimals();
        return convertTokenAmountTo(pair.stableToken, stableTokenAmount, indexTokenDec);
    }

    function convertTokenAmountTo(
        address token,
        int256 tokenAmount,
        uint8 targetDecimals
    ) internal view returns (int256 amount) {
        if (tokenAmount == 0) return 0;

        uint256 tokenDec = uint256(IERC20Metadata(token).decimals());

        uint256 tokenWad = 10 ** (PrecisionUtils.maxTokenDecimals() - tokenDec);
        uint256 targetTokenWad = 10 ** (PrecisionUtils.maxTokenDecimals() - targetDecimals);
        amount = (tokenAmount * int256(tokenWad)) / int256(targetTokenWad);
    }
}
