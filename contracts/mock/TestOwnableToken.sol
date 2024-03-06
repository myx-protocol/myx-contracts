// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract TestOwnableToken is ERC20, Ownable {
    constructor() ERC20('test', 'test') {
        _mint(msg.sender, 1000 * 1e10);
    }

    function mint(address account, uint amount) public onlyOwner {
        _mint(account, amount);
    }
}
