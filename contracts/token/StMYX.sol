// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './BaseToken.sol';

contract StMYX is BaseToken {
    constructor() ERC20('Staked MYX', 'stMYX') {}
}
