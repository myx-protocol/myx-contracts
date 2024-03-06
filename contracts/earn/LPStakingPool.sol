// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import '../token/interfaces/IBaseToken.sol';
import '../interfaces/IPool.sol';

// staking pool for MLP
contract LPStakingPool is Pausable, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IPool public pool;

    mapping(uint256 => mapping(address => uint256)) public userStaked;

    mapping(uint256 => uint256) public maxStakeAmount;

    mapping(uint256 => uint256) public totalStaked;

    mapping(address => bool) public isHandler;

    event Stake(uint256 indexed pairIndex, address indexed pairToken, address indexed account, uint256 amount);
    event Unstake(uint256 indexed pairIndex, address indexed pairToken, address indexed account, uint256 amount);

    constructor(IPool _pool) {
        pool = _pool;
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], 'LPStakingPool: handler forbidden');
        _;
    }

    function setHandler(address _handler, bool enable) external onlyOwner {
        isHandler[_handler] = enable;
    }

    function setPairInfo(IPool _pool) external onlyOwner {
        pool = _pool;
    }

    function setMaxStakeAmount(uint256 _pairIndex, uint256 _maxStakeAmount) external onlyOwner {
        maxStakeAmount[_pairIndex] = _maxStakeAmount;
    }

    function stake(uint256 pairIndex, uint256 amount) external whenNotPaused {
        _stake(pairIndex, msg.sender, msg.sender, amount);
    }

    function stakeForAccount(
        uint256 pairIndex,
        address funder,
        address account,
        uint256 amount
    ) external onlyHandler whenNotPaused {
        _stake(pairIndex, funder, account, amount);
    }

    function unstake(uint256 pairIndex, uint256 amount) external whenNotPaused {
        _unstake(pairIndex, msg.sender, msg.sender, amount);
    }

    function unstakeForAccount(
        uint256 pairIndex,
        address account,
        address receiver,
        uint256 amount
    ) external onlyHandler whenNotPaused {
        _unstake(pairIndex, account, receiver, amount);
    }

    function _stake(uint256 pairIndex, address funder, address account, uint256 amount) private {
        require(amount > 0, 'LPStakingPool: invalid stake amount');

        IPool.Pair memory pair = pool.getPair(pairIndex);
        require(pair.enable && pair.pairToken != address(0), 'LPStakingPool: invalid pair');
        require(
            userStaked[pairIndex][account] + amount <= maxStakeAmount[pairIndex],
            'LPStakingPool :exceed max stake amount'
        );

        userStaked[pairIndex][account] += amount;
        totalStaked[pairIndex] += amount;

        IERC20(pair.pairToken).safeTransferFrom(funder, address(this), amount);

        emit Stake(pairIndex, pair.pairToken, account, amount);
    }

    function _unstake(uint256 pairIndex, address account, address receiver, uint256 amount) private {
        IPool.Pair memory pair = pool.getPair(pairIndex);
        require(pair.pairToken != address(0), 'LPStakingPool: invalid pair');

        require(userStaked[pairIndex][account] > 0, 'LPStakingPool: none staked');
        require(amount > 0 && amount <= userStaked[pairIndex][account], 'LPStakingPool: invalid unstake amount');

        userStaked[pairIndex][account] -= amount;
        totalStaked[pairIndex] -= amount;

        IERC20(pair.pairToken).safeTransfer(receiver, amount);

        emit Unstake(pairIndex, pair.pairToken, account, amount);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }
}
