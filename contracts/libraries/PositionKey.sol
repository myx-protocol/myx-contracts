// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PositionKey {
    function getPositionKey(address account, uint256 pairIndex, bool isLong) internal pure returns (bytes32) {
        require(pairIndex < 2 ** (96 - 32), "ptl");
        return bytes32(
            uint256(uint160(account)) << 96 | pairIndex << 32 | (isLong ? 1 : 0)
        );
    }
}
