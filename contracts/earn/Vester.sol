// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

contract Vester is ReentrancyGuard, Ownable, Initializable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    enum DistributeType {
        TEAM_ADVISOR,
        PRIVATE_PLACEMENT,
        COMMUNITY,
        INITIAL_LIQUIDITY,
        MARKET_OPERATION,
        ECO_KEEPER,
        DEVELOPMENT_RESERVE
    }

    event Release(
        DistributeType indexed distributeType,
        address indexed recevier,
        uint256 releaseAmount,
        uint256 totalRelease,
        uint256 releasedAmount
    );

    uint256 public constant PERCENTAGE = 10000;
    uint256 public constant MONTH = 30 days;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    address public token;

    mapping(DistributeType => address) receiver;
    mapping(DistributeType => uint256) totalRelease;
    mapping(DistributeType => uint256) tge;
    mapping(DistributeType => uint256) releaseInterval;
    mapping(DistributeType => uint256) releaseRounds;
    mapping(DistributeType => uint256) nextReleaseTime;
    mapping(DistributeType => uint256) releasedAmount;

    constructor(
        address _token,
        address _teamAndAdvisorReceiver,
        address _privatePlacementReceiver,
        address _communityReceiver,
        address _initLiquidityReceiver,
        address _marketOperationReceiver,
        address _ecoKeeperReceiver,
        address _developmentReserveReceiver
    ) {
        require(_token != address(0), 'Vester: invalid token');
        token = _token;

        receiver[DistributeType.TEAM_ADVISOR] = _teamAndAdvisorReceiver;
        totalRelease[DistributeType.TEAM_ADVISOR] = (TOTAL_SUPPLY * 2000) / PERCENTAGE;
        releaseInterval[DistributeType.TEAM_ADVISOR] = MONTH;
        releaseRounds[DistributeType.TEAM_ADVISOR] = 24;
        nextReleaseTime[DistributeType.TEAM_ADVISOR] = block.timestamp + 12 * MONTH;

        receiver[DistributeType.PRIVATE_PLACEMENT] = _privatePlacementReceiver;
        totalRelease[DistributeType.PRIVATE_PLACEMENT] = (TOTAL_SUPPLY * 2000) / PERCENTAGE;
        releaseInterval[DistributeType.PRIVATE_PLACEMENT] = MONTH;
        releaseRounds[DistributeType.PRIVATE_PLACEMENT] = 18;
        nextReleaseTime[DistributeType.PRIVATE_PLACEMENT] = block.timestamp + 6 * MONTH;

        receiver[DistributeType.COMMUNITY] = _communityReceiver;
        totalRelease[DistributeType.COMMUNITY] = (TOTAL_SUPPLY * 3000) / PERCENTAGE;

        receiver[DistributeType.INITIAL_LIQUIDITY] = _initLiquidityReceiver;
        totalRelease[DistributeType.INITIAL_LIQUIDITY] = (TOTAL_SUPPLY * 550) / PERCENTAGE;

        receiver[DistributeType.MARKET_OPERATION] = _marketOperationReceiver;
        totalRelease[DistributeType.MARKET_OPERATION] = (TOTAL_SUPPLY * 800) / PERCENTAGE;
        tge[DistributeType.MARKET_OPERATION] = (totalRelease[DistributeType.MARKET_OPERATION] * 250) / PERCENTAGE;
        releaseInterval[DistributeType.MARKET_OPERATION] = 3 * MONTH;
        releaseRounds[DistributeType.MARKET_OPERATION] = 6;
        nextReleaseTime[DistributeType.MARKET_OPERATION] = block.timestamp;

        receiver[DistributeType.ECO_KEEPER] = _ecoKeeperReceiver;
        totalRelease[DistributeType.ECO_KEEPER] = (TOTAL_SUPPLY * 850) / PERCENTAGE;
        tge[DistributeType.ECO_KEEPER] = (totalRelease[DistributeType.ECO_KEEPER] * 250) / PERCENTAGE;
        releaseInterval[DistributeType.ECO_KEEPER] = 3 * MONTH;
        releaseRounds[DistributeType.ECO_KEEPER] = 6;
        nextReleaseTime[DistributeType.ECO_KEEPER] = block.timestamp;

        receiver[DistributeType.DEVELOPMENT_RESERVE] = _developmentReserveReceiver;
        totalRelease[DistributeType.DEVELOPMENT_RESERVE] = (TOTAL_SUPPLY * 800) / PERCENTAGE;
    }

    function updateReceiver(DistributeType _distributeType, address _receiver) external onlyOwner {
        require(_receiver != address(0), 'Vester: invalid receiver');
        receiver[_distributeType] = _receiver;
    }

    function releaseToken(DistributeType distributeType) external nonReentrant returns (uint256 releaseAmount) {
        require(releasedAmount[distributeType] < totalRelease[distributeType], 'Vester: all released');
        require(receiver[distributeType] != address(0), 'Vester: invalid receiver');

        if (
            distributeType == DistributeType.TEAM_ADVISOR ||
            distributeType == DistributeType.PRIVATE_PLACEMENT ||
            distributeType == DistributeType.COMMUNITY ||
            distributeType == DistributeType.INITIAL_LIQUIDITY ||
            distributeType == DistributeType.DEVELOPMENT_RESERVE
        ) {
            require(block.timestamp >= nextReleaseTime[distributeType], 'Vester: locking time');

            releaseAmount = getReleaseAmount(distributeType);
            require(releaseAmount > 0, 'Vester: none release');

            releasedAmount[distributeType] += releaseAmount;
            nextReleaseTime[distributeType] += releaseInterval[distributeType];
            IERC20(token).safeTransfer(receiver[distributeType], releaseAmount);
        } else if (
            distributeType == DistributeType.COMMUNITY ||
            distributeType == DistributeType.INITIAL_LIQUIDITY ||
            distributeType == DistributeType.DEVELOPMENT_RESERVE
        ) {
            releaseAmount = getReleaseAmount(distributeType);
            require(releaseAmount > 0, 'Vester: none release');
            releasedAmount[distributeType] += releaseAmount;
            IERC20(token).safeTransfer(receiver[distributeType], releaseAmount);
        }
        emit Release(
            distributeType,
            receiver[distributeType],
            releaseAmount,
            totalRelease[distributeType],
            releasedAmount[distributeType]
        );
    }

    function getReleaseAmount(DistributeType distributeType) public view returns (uint256 releaseAmount) {
        if (releasedAmount[distributeType] >= totalRelease[distributeType]) {
            return 0;
        }

        if (distributeType == DistributeType.TEAM_ADVISOR || distributeType == DistributeType.PRIVATE_PLACEMENT) {
            if (block.timestamp < nextReleaseTime[distributeType]) {
                return 0;
            }

            // first release
            if (releasedAmount[distributeType] == 0) {
                return totalRelease[distributeType] / releaseRounds[distributeType];
            }

            uint256 interval = block.timestamp - nextReleaseTime[distributeType];
            if (interval < releaseInterval[distributeType]) {
                return 0;
            }
            // todo releaseAmount.min(total - released)
            releaseAmount = totalRelease[distributeType] / releaseRounds[distributeType];
        } else if (distributeType == DistributeType.MARKET_OPERATION || distributeType == DistributeType.ECO_KEEPER) {

            if (block.timestamp < nextReleaseTime[distributeType]) {
                return 0;
            }

            if (releasedAmount[distributeType] == 0) {
                return tge[distributeType];
            }

            uint256 interval = block.timestamp - nextReleaseTime[distributeType];
            if (interval < releaseInterval[distributeType]) {
                return 0;
            }

            releaseAmount = (totalRelease[distributeType] - tge[distributeType]) / releaseRounds[distributeType];
        } else if (
            distributeType == DistributeType.COMMUNITY ||
            distributeType == DistributeType.INITIAL_LIQUIDITY ||
            distributeType == DistributeType.DEVELOPMENT_RESERVE
        ) {
            releaseAmount = totalRelease[distributeType] - releasedAmount[distributeType];
        }
        return releaseAmount.min(totalRelease[distributeType] - releasedAmount[distributeType]);
    }
}
