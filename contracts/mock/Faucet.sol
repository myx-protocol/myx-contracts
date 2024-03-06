// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Faucet {

    address[] public assets;

    uint256[] public amounts;

    address public admin;

    mapping(address => uint256) public interval;

    constructor(address[] memory _assets, uint256[] memory _amounts) {
        admin = msg.sender;
        assets = _assets;
        amounts = _amounts;
    }

    function getAssetList() external view returns (IERC20Metadata[] memory assetList, uint256[] memory amountList) {
        assetList = new IERC20Metadata[](assets.length);
        amountList = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            assetList[i] = IERC20Metadata(assets[i]);
            amountList[i] = amounts[i];
        }
        return (assetList, amountList);
    }

    function getAsset() external {
        require(interval[msg.sender] + 86400 <= block.timestamp, "next interval");

        bool received;
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20Metadata token = IERC20Metadata(assets[i]);

            uint256 amount = amounts[i];

            if (token.balanceOf(address(this)) >= amount) {
                token.transfer(msg.sender, amount);
                received = true;
            }
        }

        if (received) {
            interval[msg.sender] = block.timestamp;
        }
    }

    function adminTransfer(address asset, address recipient) external {
        require(msg.sender == admin, "not admin");

        IERC20Metadata token = IERC20Metadata(asset);
        token.transfer(recipient, token.balanceOf(address(this)));
    }
}
