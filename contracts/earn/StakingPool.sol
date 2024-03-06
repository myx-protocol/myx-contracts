// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import '../token/interfaces/IBaseToken.sol';
import './interfaces/IStakingPool.sol';
import './interfaces/IRewardDistributor.sol';
import '../interfaces/IFeeCollector.sol';

// staking pool for MYX / raMYX
contract StakingPool is IStakingPool, Pausable, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant PRECISION = 1e30;

    IRewardDistributor rewardDistributor;

    address public stToken;
    address public rewardToken;
    mapping(address => bool) public isStakeToken;
    mapping(address => uint256) public maxStakeAmount;
    // rewardToken -> stakeAmount
    mapping(address => uint256) public totalStaked;
    // rewardToken -> user -> stakeAmount
    mapping(address => mapping(address => uint256)) public userStaked;

    IFeeCollector public feeCollector;

    uint256 public cumulativeRewardPerToken;
    mapping(address => uint256) public userCumulativeRewardPerTokens;

    mapping(address => bool) public isHandler;

    event Stake(address indexed stakeToken, address indexed account, uint256 amount);
    event Unstake(address indexed stakeToken, address indexed account, uint256 amount);
    event Claim(address receiver, uint256 amount);

    constructor(
        address[] memory _stakeTokens,
        address _stToken,
        address _rewardToken,
        IFeeCollector _feeCollector
    ) {
        for (uint256 i = 0; i < _stakeTokens.length; i++) {
            address stakeToken = _stakeTokens[i];
            isStakeToken[stakeToken] = true;
        }
        stToken = _stToken;
        rewardToken = _rewardToken;
        feeCollector = _feeCollector;
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], 'StakingPool: handler forbidden');
        _;
    }

    function setHandler(address _handler, bool enable) external onlyOwner {
        isHandler[_handler] = enable;
    }

    function setStakeToken(address _stakeToken, bool _isStakeToken) external onlyOwner {
        isStakeToken[_stakeToken] = _isStakeToken;
    }

    function setMaxStakeAmount(address _stakeToken, uint256 _maxStakeAmount) external onlyOwner {
        maxStakeAmount[_stakeToken] = _maxStakeAmount;
    }

    function stake(address stakeToken, uint256 amount) external whenNotPaused {
        _stake(msg.sender, msg.sender, stakeToken, amount);
    }

    function stakeForAccount(
        address funder,
        address account,
        address stakeToken,
        uint256 amount
    ) external override onlyHandler whenNotPaused {
        _stake(funder, account, stakeToken, amount);
    }

    function unstake(address stakeToken, uint256 amount) external whenNotPaused {
        _unstake(msg.sender, msg.sender, stakeToken, amount);
    }

    function unstakeForAccount(
        address account,
        address receiver,
        address stakeToken,
        uint256 amount
    ) external override onlyHandler whenNotPaused {
        _unstake(account, receiver, stakeToken, amount);
    }

    function _stake(address funder, address account, address stakeToken, uint256 amount) private {
        require(isStakeToken[stakeToken], 'StakingPool: invalid depositToken');
        require(amount > 0, 'StakingPool: invalid stake amount');
        require(
            userStaked[stakeToken][account] + amount <= maxStakeAmount[stakeToken],
            'StakingPool: exceed max stake amount'
        );
        _claimReward(account);

        userStaked[stakeToken][account] += amount;
        totalStaked[stakeToken] += amount;

        IERC20(stakeToken).safeTransferFrom(funder, address(this), amount);
        IBaseToken(stToken).mint(account, amount);

        emit Stake(stakeToken, account, amount);
    }

    function _unstake(address account, address receiver, address stakeToken, uint256 amount) private {
        require(isStakeToken[stakeToken], 'StakingPool: invalid depositToken');
        require(amount > 0, 'StakingPool: invalid stake amount');
        require(amount <= userStaked[stakeToken][account], 'StakingPool: exceed staked amount');

        _claimReward(account);

        userStaked[stakeToken][account] -= amount;
        totalStaked[stakeToken] -= amount;

        IERC20(stakeToken).safeTransfer(receiver, amount);
        IBaseToken(stToken).burn(account, amount);

        emit Unstake(stakeToken, account, amount);
    }

    function claimReward() external whenNotPaused {
        _claimReward(msg.sender);
    }

    function _claimReward(address account) internal returns (uint256 claimReward) {
        uint256 totalSupply = IERC20(stToken).totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        uint256 pendingReward = feeCollector.claimStakingTradingFee();
        if (pendingReward > 0) {
            cumulativeRewardPerToken += pendingReward.mulDiv(PRECISION, totalSupply);
        }
        uint256 balance = IERC20(stToken).balanceOf(account);
        uint256 claimableReward = balance.mulDiv(
            cumulativeRewardPerToken - userCumulativeRewardPerTokens[account],
            PRECISION
        );
        IERC20(rewardToken).safeTransfer(account, claimableReward);
        userCumulativeRewardPerTokens[account] = cumulativeRewardPerToken;
    }

    function claimableReward(address account) public view returns (uint256 claimableReward) {
        uint256 totalSupply = IERC20(stToken).totalSupply();
        uint256 balance = IERC20(stToken).balanceOf(account);
        if (totalSupply == 0 || balance == 0) {
            return 0;
        }
        uint256 pendingReward = feeCollector.stakingTradingFee();
        uint256 nextCumulativeFeePerToken = cumulativeRewardPerToken + pendingReward.mulDiv(PRECISION, totalSupply);
        claimableReward = balance.mulDiv(nextCumulativeFeePerToken - userCumulativeRewardPerTokens[account], PRECISION);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }
}
