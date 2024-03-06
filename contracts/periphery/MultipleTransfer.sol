// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MultipleTransfer is Pausable, Ownable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    bytes32 public constant MERKLE_MANAGER_ROLE = keccak256("MERKLE_MANAGER");

    bytes32 public merkleRoot;

    constructor() Ownable() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyOperator() {
        _checkRole(OPERATOR_ROLE);
        _;
    }

    modifier onlyMerkleManager() {
        _checkRole(MERKLE_MANAGER_ROLE);
        _;
    }

    receive() external payable {}

    function addOperator(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, account);
    }

    function addMerkleManager(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MERKLE_MANAGER_ROLE, account);
    }

    function updateMerkleRoot(bytes32 _merkleRoot) external onlyMerkleManager {
        merkleRoot = _merkleRoot;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function batchTransferETH(
        address[] memory recipients,
        uint256[] memory amounts,
        bytes32[][] memory proofs
    ) public onlyOperator whenNotPaused {
        require(recipients.length == amounts.length, "Recipients and amounts length mismatch");

        for (uint i = 0; i < recipients.length; i++) {
            bytes32 leaf = keccak256(abi.encodePacked(recipients[i]));
            require(MerkleProof.verify(proofs[i], merkleRoot, leaf), "Invalid Merkle Proof");

            payable(recipients[i]).transfer(amounts[i]);
        }
    }

    function batchTransferERC20(
        IERC20 token,
        address[] memory recipients,
        uint256[] memory amounts,
        bytes32[][] memory proofs
    ) public onlyOperator whenNotPaused {
        require(recipients.length == amounts.length, "Recipients and amounts length mismatch");

        for (uint i = 0; i < recipients.length; i++) {
            bytes32 leaf = keccak256(abi.encodePacked(recipients[i]));
            require(MerkleProof.verify(proofs[i], merkleRoot, leaf), "Invalid Merkle Proof");
            token.safeTransfer(recipients[i], amounts[i]);
        }
    }

    function emergencyWithdrawETH(address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }

    function emergencyWithdrawERC20(IERC20 token, address recipient) public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(recipient, balance);
    }

}
