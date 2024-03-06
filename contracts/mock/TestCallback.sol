// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPool.sol";
import "../interfaces/ILiquidityCallback.sol";
import "../interfaces/ISwapCallback.sol";

contract TestCallBack is ILiquidityCallback, ISwapCallback {
    function addLiquidity(
        address pool,
        address indexToken,
        address stableToken,
        uint256 indexAmount,
        uint256 stableAmount
    ) external {
        uint256 pairIndex = IPool(pool).getPairIndex(indexToken, stableToken);
        IPool(pool).addLiquidity(
            msg.sender,
            pairIndex,
            indexAmount,
            stableAmount,
            abi.encode(msg.sender)
        );
    }

    function addLiquidityForAccount(
        address pool,
        address indexToken,
        address stableToken,
        address receiver,
        uint256 indexAmount,
        uint256 stableAmount
    ) external {
        uint256 pairIndex = IPool(pool).getPairIndex(indexToken, stableToken);
        IPool(pool).addLiquidity(
            receiver,
            pairIndex,
            indexAmount,
            stableAmount,
            abi.encode(msg.sender)
        );
    }

    function addLiquidityCallback(
        address indexToken,
        address stableToken,
        uint256 amountIndex,
        uint256 amountStable,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        if (amountIndex > 0) {
            IERC20(indexToken).transferFrom(sender, msg.sender, uint256(amountIndex));
        }
        if (amountStable > 0) {
            IERC20(stableToken).transferFrom(sender, msg.sender, uint256(amountStable));
        }
    }

    function removeLiquidity(
        address pool,
        address indexToken,
        address stableToken,
        uint256 amount,
        bool useETH
    ) external {
        uint256 pairIndex = IPool(pool).getPairIndex(indexToken, stableToken);
        IPool(pool).removeLiquidity(
            payable(msg.sender),
            pairIndex,
            amount,
            useETH,
            abi.encode(msg.sender)
        );
    }

    function removeLiquidityForAccount(
        address pool,
        address indexToken,
        address stableToken,
        address receiver,
        uint256 amount,
        bool useETH
    ) external {
        uint256 pairIndex = IPool(pool).getPairIndex(indexToken, stableToken);
        IPool(pool).removeLiquidity(
            payable(receiver),
            pairIndex,
            amount,
            useETH,
            abi.encode(msg.sender)
        );
    }

    function removeLiquidityCallback(
        address pairToken,
        uint256 amount,
        bytes calldata data
    ) external {
        address sender = abi.decode(data, (address));
        IERC20(pairToken).transferFrom(sender, msg.sender, amount);
    }

    function swapCallback(
        address indexToken,
        address stableToken,
        uint256 indexAmount,
        uint256 stableAmount,
        bytes calldata data
    ) external {
        address sender = abi.decode(data, (address));

        if (indexAmount > 0) {
            IERC20(indexToken).transferFrom(sender, msg.sender, indexAmount);
        } else if (stableAmount > 0) {
            IERC20(stableToken).transferFrom(sender, msg.sender, stableAmount);
        }
    }
}
