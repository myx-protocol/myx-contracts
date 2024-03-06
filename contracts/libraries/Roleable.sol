// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";

abstract contract Roleable {
    IAddressesProvider public immutable ADDRESS_PROVIDER;

    constructor(IAddressesProvider _addressProvider) {
        ADDRESS_PROVIDER = _addressProvider;
    }

    modifier onlyAdmin() {
        require(IRoleManager(ADDRESS_PROVIDER.roleManager()).isAdmin(msg.sender), "onlyAdmin");
        _;
    }

    modifier onlyPoolAdmin() {
        require(
            IRoleManager(ADDRESS_PROVIDER.roleManager()).isPoolAdmin(msg.sender),
            "onlyPoolAdmin"
        );
        _;
    }
}
