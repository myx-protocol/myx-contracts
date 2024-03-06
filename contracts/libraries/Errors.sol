// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Errors {
    string public constant CALLER_NOT_POOL_ADMIN = "onlyPoolAdmin"; // The caller of the function is not a pool admin
    string public constant NOT_ADDRESS_ZERO = "is 0"; // The caller of the function is not a pool admin
}
