// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import '../token/interfaces/IBaseToken.sol';

contract Convertor is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public convertToken;
    address public claimToken;
    address public communityPool;

    struct Conversion {
        uint256 initAmount;
        uint256 convertAmount;
        uint256 lockPeriod;
        uint256 lastVestingTimes;
        uint256 claimedAmount;
    }

    event Convert(
        address indexed account,
        uint256 initAmount,
        uint256 lockDays,
        uint256 convertAmount,
        uint256 remainingAmount
    );

    event Claim(address indexed account, uint256 amount);

    mapping(address => Conversion[]) public userConversions;

    constructor(address _convertToken, address _claimToken) {
        convertToken = _convertToken;
        claimToken = _claimToken;
    }

    function setCommunityPool(address _communityPool) external onlyOwner {
        communityPool = _communityPool;
    }

    function convert(uint256 amount, uint256 lockDays) external {
        require(
            lockDays == 0 || lockDays == 14 || lockDays == 30 || lockDays == 90 || lockDays == 180,
            'Convertor: invalid unlock period'
        );

        // claim before convert
        _claim(msg.sender);

        IERC20(convertToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 convertAmount;
        if (lockDays == 0) {
            convertAmount = (amount * 50) / 100;
        } else if (lockDays == 14) {
            convertAmount = (amount * 60) / 100;
        } else if (lockDays == 30) {
            convertAmount = (amount * 70) / 100;
        } else if (lockDays == 90) {
            convertAmount = (amount * 85) / 100;
        } else if (lockDays == 180) {
            convertAmount = amount;
        }

        // burn remaining raMYX and transfer myx
        uint256 remainingAmount = amount - convertAmount;
        IBaseToken(convertToken).burn(address(this), remainingAmount);
        IERC20(claimToken).safeTransfer(communityPool, remainingAmount);

        // convert immediately
        if (lockDays == 0) {
            IBaseToken(convertToken).burn(address(this), convertAmount);
            IERC20(claimToken).safeTransfer(msg.sender, convertAmount);
        } else {
            userConversions[msg.sender].push(Conversion(amount, convertAmount, lockDays * 1 days, block.timestamp, 0));
        }

        emit Convert(msg.sender, amount, lockDays, convertAmount, remainingAmount);
    }

    function claim() external {
        _claim(msg.sender);
    }

    function _claim(address account) internal {
        address account = msg.sender;

        Conversion[] storage conversions = userConversions[account];

        if (conversions.length == 0) {
            return;
        }
        uint256 claimableAmount;
        for (uint256 i = conversions.length - 1; i >= 0; i--) {
            Conversion storage conversion = conversions[i];
            uint256 timeDiff = block.timestamp - conversion.lastVestingTimes;
            uint256 nextVestedAmount = (conversion.convertAmount * timeDiff) / conversion.lockPeriod;

            if (nextVestedAmount + conversion.claimedAmount >= conversion.convertAmount) {
                nextVestedAmount = conversion.convertAmount - conversion.claimedAmount;
                // remove conversion
                Conversion storage lastConversion = conversions[conversions.length - 1];
                conversions[i] = lastConversion;
                conversions.pop();
            } else {
                conversion.claimedAmount += nextVestedAmount;
                conversion.lastVestingTimes = block.timestamp;
            }
            claimableAmount += nextVestedAmount;
            if (conversions.length == 0 || i == 0) {
                break;
            }
        }

        IBaseToken(convertToken).burn(address(this), claimableAmount);
        IERC20(claimToken).safeTransfer(account, claimableAmount);

        emit Claim(msg.sender, claimableAmount);
    }

    function claimableAmount(address _account) public view returns (uint256 claimableAmount) {
        Conversion[] memory conversions = userConversions[_account];
        for (uint256 i = 0; i < conversions.length; i++) {
            Conversion memory conversion = conversions[i];
            uint256 timeDiff = block.timestamp - conversion.lastVestingTimes;
            uint256 nextVestedAmount = (conversion.convertAmount * timeDiff) / conversion.lockPeriod;

            if (nextVestedAmount + conversion.claimedAmount >= conversion.convertAmount) {
                nextVestedAmount = conversion.convertAmount - conversion.claimedAmount;
            }
            claimableAmount += nextVestedAmount;
        }
    }

    function totalConverts(
        address _account
    ) public view returns (uint256 amount, uint256 convertAmount, uint256 claimedAmount) {
        Conversion[] memory conversions = userConversions[_account];
        for (uint256 i = 0; i < conversions.length; i++) {
            Conversion memory conversion = conversions[i];
            amount += conversion.initAmount;
            convertAmount += conversion.convertAmount;
            claimedAmount += conversion.claimedAmount;
        }
    }
}
