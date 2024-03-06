// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "../token/interfaces/IBaseToken.sol";
import "./interfaces/IRewardDistributor.sol";
import "../interfaces/IPositionManager.sol";

// distribute reward myx for staking
contract FeeDistributor is IRewardDistributor, Pausable, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address public rewardToken;

    // increment after update root
    uint256 public round;

    // merkle root for round
    mapping(uint256 => bytes32) public merkleRoots;

    mapping(bytes32 => bool) public merkleRootUsed;

    mapping(uint256 => mapping(address => bool)) public userClaimed;

    // total rewards claimed by user
    mapping(address => uint256) public userClaimedAmount;

    uint256 public totalReward;

    uint256 public totalClaimed;

    mapping(address => bool) public isHandler;

    IPositionManager public positionManager;

    event Claim(address indexed account, uint256 indexed round, uint256 amount);
    event Compound(address indexed account, uint256 indexed round, uint256 amount);

    constructor(address _rewardToken) {
        rewardToken = _rewardToken;
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], "RewardDistributor: handler forbidden");
        _;
    }

    function setHandler(address _handler, bool enable) external onlyOwner {
        isHandler[_handler] = enable;
    }

    function setPositionManager(IPositionManager _positionManager) external onlyOwner {
        positionManager = _positionManager;
    }

    // update root by handler
    // amount: total reward
    function updateRoot(
        bytes32 _merkleRoot,
        uint256 transferInAmount,
        uint256 _amount
    ) external override onlyHandler {
        require(!merkleRootUsed[_merkleRoot], "RewardDistributor: root already used");
        require(totalReward + transferInAmount >= _amount, "RewardDistributor: reward not enough");
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), transferInAmount);

        round++;
        merkleRoots[round] = _merkleRoot;
        merkleRootUsed[_merkleRoot] = true;
        totalReward += transferInAmount;
    }

    // claim reward by user
    function claim(
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external whenNotPaused nonReentrant {
        _claim(msg.sender, msg.sender, _amount, round, _merkleProof);
    }

    // claim reward by handler
    function claimForAccount(
        address account,
        address receiver,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external override onlyHandler whenNotPaused nonReentrant {
        _claim(account, receiver, _amount, round, _merkleProof);
    }

    function _claim(
        address account,
        address receiver,
        uint256 _amount,
        uint256 _round,
        bytes32[] calldata _merkleProof
    ) private returns (uint256) {
        require(!userClaimed[_round][account], "RewardDistributor: already claimed");

        (bool canClaim, uint256 adjustedAmount) = _canClaim(account, _amount, _merkleProof);

        require(canClaim, "RewardDistributor: cannot claim");

        userClaimed[_round][account] = true;

        userClaimedAmount[account] += adjustedAmount;
        totalClaimed += adjustedAmount;

        IBaseToken(rewardToken).mint(receiver, adjustedAmount);

        emit Claim(account, _round, adjustedAmount);
        return adjustedAmount;
    }

    function canClaim(
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external view returns (bool, uint256) {
        return _canClaim(msg.sender, _amount, _merkleProof);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function _canClaim(
        address account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) private view returns (bool, uint256) {
        bytes32 node = keccak256(abi.encodePacked(account, _amount));
        bool canClaim = MerkleProof.verify(_merkleProof, merkleRoots[round], node);

        if ((!canClaim) || (userClaimed[round][account])) {
            return (false, 0);
        } else {
            return (true, _amount - userClaimedAmount[account]);
        }
    }
}
