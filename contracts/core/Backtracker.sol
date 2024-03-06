// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../interfaces/IBacktracker.sol";
import "../interfaces/IAddressesProvider.sol";
import "../interfaces/IRoleManager.sol";

contract Backtracker is IBacktracker {

    IAddressesProvider public immutable ADDRESS_PROVIDER;

    bool public override backtracking;
    uint64 public override backtrackRound;
    address public executor;

    constructor(IAddressesProvider addressProvider) {
        ADDRESS_PROVIDER = addressProvider;
        backtracking = false;
    }

    modifier whenNotBacktracking() {
        _requireNotBacktracking();
        _;
    }

    modifier whenBacktracking() {
        _requireBacktracking();
        _;
    }

    modifier onlyPoolAdmin() {
        require(IRoleManager(ADDRESS_PROVIDER.roleManager()).isPoolAdmin(msg.sender), "only poolAdmin");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "only executor");
        _;
    }

    function updateExecutorAddress(address newAddress) external onlyPoolAdmin {
        address oldAddress = executor;
        executor = newAddress;
        emit UpdatedExecutorAddress(msg.sender, oldAddress, newAddress);
    }

    function enterBacktracking(uint64 _backtrackRound) external whenNotBacktracking onlyExecutor {
        backtracking = true;
        backtrackRound = _backtrackRound;
        emit Backtracking(msg.sender, _backtrackRound);
    }

    function quitBacktracking() external whenBacktracking onlyExecutor {
        backtracking = false;
        emit UnBacktracking(msg.sender);
    }

    function _requireNotBacktracking() internal view {
        require(!backtracking, "Backtracker: backtracking");
    }

    function _requireBacktracking() internal view {
        require(backtracking, "Backtracker: not backtracking");
    }
}
