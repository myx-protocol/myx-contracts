// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/IPoolTokenFactory.sol";
import "./PoolToken.sol";

contract PoolTokenFactory is IPoolTokenFactory {
    IAddressesProvider public immutable ADDRESS_PROVIDER;

    constructor(IAddressesProvider addressProvider) {
        ADDRESS_PROVIDER = addressProvider;
    }

    function createPoolToken(
        address indexToken,
        address stableToken
    ) external override returns (address) {
        string memory name = string(
            abi.encodePacked(
                IERC20Metadata(indexToken).name(),
                "-",
                IERC20Metadata(stableToken).name(),
                "-lp"
            )
        );
        string memory symbol = string(
            abi.encodePacked(
                IERC20Metadata(indexToken).symbol(),
                "-",
                IERC20Metadata(stableToken).symbol(),
                "-lp"
            )
        );
        PoolToken pairToken = new PoolToken(
            ADDRESS_PROVIDER,
            indexToken,
            stableToken,
            msg.sender,
            name,
            symbol
        );
        return address(pairToken);
    }
}
