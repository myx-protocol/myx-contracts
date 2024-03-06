// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAddressesProvider.sol";
import "./libraries/Errors.sol";

contract AddressesProvider is Ownable, Initializable, IAddressesProvider {
    bytes32 private constant TIMELOCK = "TIMELOCK";
    bytes32 private constant ROLE_MANAGER = "ROLE_MANAGER";
    bytes32 private constant PRICE_ORACLE = "PRICE_ORACLE";
    bytes32 private constant INDEX_PRICE_ORACLE = "INDEX_PRICE_ORACLE";
    bytes32 private constant FUNDING_RATE = "FUNDING_RATE";
    bytes32 private constant EXECUTION_LOGIC = "EXECUTION_LOGIC";
    bytes32 private constant LIQUIDATION_LOGIC = "LIQUIDATION_LOGIC";
    bytes32 private constant BACKTRACKER = "BACKTRACKER";

    address public immutable override WETH;

    mapping(bytes32 => address) private _addresses;

    constructor(address _weth, address _timelock) {
        WETH = _weth;
        setAddress(TIMELOCK, _timelock);
    }

    modifier onlyTimelock() {
        require(msg.sender == _addresses[TIMELOCK], "only timelock");
        _;
    }

    function initialize(
        address _priceOracle,
        address _indexPriceOracle,
        address _fundingRate,
        address _executionLogic,
        address _liquidationLogic,
        address _backtracker
    ) external onlyOwner initializer {
        setAddress(PRICE_ORACLE, _priceOracle);
        setAddress(INDEX_PRICE_ORACLE, _indexPriceOracle);
        setAddress(FUNDING_RATE, _fundingRate);
        setAddress(EXECUTION_LOGIC, _executionLogic);
        setAddress(LIQUIDATION_LOGIC, _liquidationLogic);
        setAddress(BACKTRACKER, _backtracker);
    }

    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }

    function timelock() external view override returns (address) {
        return getAddress(TIMELOCK);
    }

    function roleManager() external view override returns (address) {
        return getAddress(ROLE_MANAGER);
    }

    function priceOracle() external view override returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    function indexPriceOracle() external view override returns (address) {
        return getAddress(INDEX_PRICE_ORACLE);
    }

    function fundingRate() external view override returns (address) {
        return getAddress(FUNDING_RATE);
    }

    function executionLogic() external view override returns (address) {
        return getAddress(EXECUTION_LOGIC);
    }

    function liquidationLogic() external view override returns (address) {
        return getAddress(LIQUIDATION_LOGIC);
    }

    function backtracker() external view override returns (address) {
        return getAddress(BACKTRACKER);
    }

    function setAddress(bytes32 id, address newAddress) public onlyOwner {
        address oldAddress = _addresses[id];
        _addresses[id] = newAddress;
        emit AddressSet(id, oldAddress, newAddress);
    }

    function setTimelock(address newAddress) public onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[TIMELOCK];
        _addresses[TIMELOCK] = newAddress;
        emit AddressSet(TIMELOCK, oldAddress, newAddress);
    }

    function setPriceOracle(address newAddress) external onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[PRICE_ORACLE];
        _addresses[PRICE_ORACLE] = newAddress;
        emit AddressSet(PRICE_ORACLE, oldAddress, newAddress);
    }

    function setIndexPriceOracle(address newAddress) external onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[INDEX_PRICE_ORACLE];
        _addresses[INDEX_PRICE_ORACLE] = newAddress;
        emit AddressSet(INDEX_PRICE_ORACLE, oldAddress, newAddress);
    }

    function setFundingRate(address newAddress) external onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[FUNDING_RATE];
        _addresses[FUNDING_RATE] = newAddress;
        emit AddressSet(FUNDING_RATE, oldAddress, newAddress);
    }

    function setExecutionLogic(address newAddress) external onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[EXECUTION_LOGIC];
        _addresses[EXECUTION_LOGIC] = newAddress;
        emit AddressSet(EXECUTION_LOGIC, oldAddress, newAddress);
    }

    function setLiquidationLogic(address newAddress) external onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[LIQUIDATION_LOGIC];
        _addresses[LIQUIDATION_LOGIC] = newAddress;
        emit AddressSet(LIQUIDATION_LOGIC, oldAddress, newAddress);
    }

    function setBacktracker(address newAddress) external onlyTimelock {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        address oldAddress = _addresses[BACKTRACKER];
        _addresses[BACKTRACKER] = newAddress;
        emit AddressSet(BACKTRACKER, oldAddress, newAddress);
    }

    function setRolManager(address newAddress) external onlyOwner {
        require(newAddress != address(0), Errors.NOT_ADDRESS_ZERO);
        setAddress(ROLE_MANAGER, newAddress);
    }
}
