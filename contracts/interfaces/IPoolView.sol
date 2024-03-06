// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPoolView {

    event UpdatePool(address sender, address oldAddress, address newAddress);

    event UpdatePositionManager(address sender, address oldAddress, address newAddress);

    function getMintLpAmount(
        uint256 _pairIndex,
        uint256 _indexAmount,
        uint256 _stableAmount,
        uint256 price
    ) external view returns (
            uint256 mintAmount,
            address slipToken,
            uint256 slipAmount,
            uint256 indexFeeAmount,
            uint256 stableFeeAmount,
            uint256 afterFeeIndexAmount,
            uint256 afterFeeStableAmount
        );

    function getDepositAmount(
        uint256 _pairIndex,
        uint256 _lpAmount,
        uint256 price
    ) external view returns (uint256 depositIndexAmount, uint256 depositStableAmount);

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
    );

    function lpFairPrice(uint256 _pairIndex, uint256 price) external view returns (uint256);
}
