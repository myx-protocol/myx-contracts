// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/AggregatorV3Interface.sol";

contract MockChainLink is AggregatorV3Interface {
    uint80[] roundIds;
    int256[] answers;

    uint256[] timestamps;

    function getRoundData(
        uint80
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundIds[0];
        return (1, 0, 1, 1, 1);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint256 index = roundIds.length - 1;
        return (roundIds[index], answers[index], 8, timestamps[index], 1);
    }

    function latestAnswer() external view returns (int256) {
        uint256 index = roundIds.length - 1;
        return answers[index];
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function setAnswer(uint80 _roundId, int256 _answer, uint256 _updatedAt) external {
        roundIds.push(_roundId);
        answers.push(_answer);
        timestamps.push(_updatedAt);
    }
}
