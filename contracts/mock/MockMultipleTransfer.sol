// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockMultipleTransfer {

    constructor(){
    }

    function sendEthToMultipleAddresses(address payable[] memory recipients, uint256[] memory amounts) public payable {
        require(recipients.length == amounts.length, "Arrays must have the same length");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(amounts[i] > 0 && amounts[i] < 1 ether, "Amount must be greater than 0 and less than 1 ether");
            recipients[i].transfer(amounts[i]);
        }
    }

    function sendTokensToMultipleAddresses(
        address tokenAddress,
        address[] memory recipients,
        uint256[] memory amounts
    ) public {
        require(recipients.length == amounts.length, "Arrays must have the same length");

        IERC20 token = IERC20(tokenAddress);

        for (uint256 i = 0; i < recipients.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(token.transfer(recipients[i], amounts[i]), "Transfer failed");
        }
    }

    receive() external payable {}

    function withdrawBalance(address admin) public {
        payable(admin).transfer(address(this).balance);
    }
}
