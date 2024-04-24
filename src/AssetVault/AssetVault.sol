// SPDX-License-Identifier: MIT
pragma solidity =0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AssetVault is AccessControl {
    struct UserDeposit {
        uint256 totalValue; // Total value deposited at the recorded time
        mapping(address => uint256) assetBalances; // Balance of each asset deposited by the user
    }

    AggregatorV3Interface internal dataFeed;
    bytes32 public constant VAULT_MANAGER_ROLE =
        keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IERC20[] public supportedAssets;
    mapping(address => uint256) public totalVaultBalance;
    mapping(address => AggregatorV3Interface) assetToOracle; // Store oracle addresses
    mapping(address => UserDeposit) public userDeposits;
    mapping(address => uint256) public userProfits;

    uint256 public performanceFeePercentage;
    uint256 public lastRecordedProfit;
    uint256 public totalProfits;

    constructor(
        address _vaultManager,
        address[] memory _initialAssets,
        uint256 _performanceFee,
        address _owner
    ) {
        grantRole(VAULT_MANAGER_ROLE, _vaultManager);
        grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _setRoleAdmin(VAULT_MANAGER_ROLE, ADMIN_ROLE); // Admins can manage vault manager role
        for (uint256 i = 0; i < _initialAssets.length; i++) {
            supportedAssets.push(IERC20(_initialAssets[i]));
        }
        performanceFeePercentage = _performanceFee;
        lastRecordedProfit = 0; // Initialize on contract creation
    }

    function setAssetToOracle(address _asset, address _oracle)
        external
        onlyRole(ADMIN_ROLE)
    {
        assetToOracle[_asset] = AggregatorV3Interface(_oracle);
    }

    function estimateVaultValue() public view returns (uint256) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            totalValue += estimateAssetValue(
                address(supportedAssets[i]),
                totalVaultBalance[address(supportedAssets[i])]
            );
        }
        return totalValue;
    }

    function deposit(address _asset, uint256 _amount) external {
        require(isAssetSupported(IERC20(_asset)), "Asset not supported");
        IERC20(_asset).transferFrom(_msgSender(), address(this), _amount);
        totalVaultBalance[_asset] += _amount;
        userDeposits[_msgSender()].totalValue += estimateAssetValue(
            _asset,
            _amount
        );
        userDeposits[_msgSender()].assetBalances[_asset] += _amount;
    }

    function withdraw(address _asset, uint256 _amount) external {
        require(
            userDeposits[_msgSender()].assetBalances[_asset] >= _amount,
            "Insufficient balance"
        );
        userDeposits[_msgSender()].assetBalances[_asset] -= _amount;
        totalVaultBalance[_asset] -= _amount;
        IERC20(_asset).transfer(_msgSender(), _amount);

        // Proportional Profit Calculation (more on this below)
        uint256 profitShare = calculateUserProfitShare(_msgSender());
        userProfits[_msgSender()] += profitShare;

        // Update user deposit records accordingly
        userDeposits[_msgSender()].totalValue -= estimateAssetValue(
            _asset,
            _amount
        );
        userDeposits[_msgSender()].assetBalances[_asset] -= _amount;
    }

    function calculateUserProfitShare(address _user)
        internal
        view
        returns (uint256)
    {
        uint256 userShare = (userDeposits[_user].totalValue * 1e18) /
            estimateVaultValue(); // 1e18 for decimals precision if needed
        uint256 profitShare = (totalProfits * userShare) / 1e18;
        return profitShare;
    }

    function trade(
        IERC20 _asset1,
        uint256 _amount1,
        IERC20 _asset2,
        uint256 _amount2
    ) external onlyRole(VAULT_MANAGER_ROLE) {
        // Logic to execute the trade on Uniswap
        // Simplified profit estimation:
        uint256 currentValue = estimateAssetValue(address(_asset2), _amount2); // Assuming you fetch the value of received assets
        uint256 previousValue = estimateAssetValue(address(_asset1), _amount1);
        uint256 profit = currentValue - previousValue;
        totalProfits += profit;
    }

    function isAssetSupported(IERC20 _asset) internal view returns (bool) {
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == _asset) {
                return true;
            }
        }
        return false;
    }

    function estimateAssetValue(address _asset, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = assetToOracle[_asset];
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 value = uint256(price) * _amount;
        return value;
    }

    function estimateAssetValueUSD(address _asset, uint256 _amount)
        public
        view
        returns (uint256 valueUSD)
    {
        AggregatorV3Interface priceFeed = assetToOracle[_asset];
        require(
            priceFeed != AggregatorV3Interface(address(0)),
            "Oracle not set for asset"
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price data");
        uint256 decimals = uint256(priceFeed.decimals());
        valueUSD = (_amount * uint256(price)) / (10**decimals);
    }

    function calculateProfits() internal view returns (uint256) {
        // uint256 currentVaultValue = totalVaultBalance; // (Adjust based on your valuation strategy)
        // uint256 generatedProfit = currentVaultValue - lastRecordedProfit;
        // return generatedProfit;
    }

    function collectPerformanceFee() external onlyRole(VAULT_MANAGER_ROLE) {
        uint256 profits = calculateProfits();
        if (profits > 0) {
            uint256 performanceFee = (profits * performanceFeePercentage) / 100;
            // Transfer performanceFee to vaultManager (mechanism depends on your setup)
            lastRecordedProfit = performanceFee;
            // lastRecordedProfit = totalVaultBalance;
        }
    }
}
