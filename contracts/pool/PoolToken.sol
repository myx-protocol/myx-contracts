// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IPoolToken.sol";

import "../libraries/Roleable.sol";

contract PoolToken is IPoolToken, Roleable, ERC20 {
    address public indexToken;
    address public stableToken;

    mapping(address => bool) public miners;

    constructor(
        IAddressesProvider addressProvider,
        address _indexToken,
        address _stableToken,
        address _miner,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) Roleable(addressProvider) {
        indexToken = _indexToken;
        stableToken = _stableToken;
        miners[_miner] = true;
    }

    modifier onlyMiner() {
        require(miners[msg.sender], "miner forbidden");
        _;
    }

    function mint(address to, uint256 amount) external onlyMiner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function setMiner(address account, bool enable) external {
        require(msg.sender == ADDRESS_PROVIDER.timelock(), "onlyTimelock");
        miners[account] = enable;
    }
}
