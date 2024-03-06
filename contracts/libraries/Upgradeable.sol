// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";

contract Upgradeable is Initializable, UUPSUpgradeable {
    IAddressesProvider public ADDRESS_PROVIDER;

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

    function _authorizeUpgrade(address) internal virtual override {
        require(msg.sender == ADDRESS_PROVIDER.timelock(), "Unauthorized access");
    }
}
