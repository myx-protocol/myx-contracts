// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IBaseToken.sol";

abstract contract BaseToken is IBaseToken, ERC20, Ownable {
    bool public privateTransferMode;

    mapping(address => bool) public miners;
    mapping(address => bool) public isHandler;

    modifier onlyMiner() {
        require(miners[msg.sender], "miner forbidden");
        _;
    }

    function setPrivateTransferMode(bool _privateTransferMode) external onlyOwner {
        privateTransferMode = _privateTransferMode;
    }

    function setMiner(address account, bool enable) external virtual onlyOwner {
        miners[account] = enable;
    }

    function setHandler(address _handler, bool enable) external onlyOwner {
        isHandler[_handler] = enable;
    }

    function mint(address to, uint256 amount) public virtual onlyMiner {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public virtual onlyMiner {
        _burn(account, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (privateTransferMode) {
            require(isHandler[msg.sender], "msg.sender not whitelisted");
        }
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        if (privateTransferMode) {
            require(isHandler[msg.sender], "msg.sender not whitelisted");
        }
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
