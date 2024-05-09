// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ITradingContract } from "../Trade/ITrade.sol";
import { IVaultManager } from "../VaultManager/IVaultManager.sol";

contract AssetVault is AccessControl {
    struct UserShares {
        uint256 totalShares;
        mapping(address => uint256) assetShares;
    }

    mapping(address => UserShares) private userShares;

    AggregatorV3Interface internal dataFeed;
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IERC20[] public supportedAssets;
    mapping(address => uint256) public totalVaultBalance;
    mapping(address => AggregatorV3Interface) assetToOracle; // Store oracle addresses
    // mapping(address => uint256) public userProfits;

    address private _admin;
    address private _vaultManager;
    uint24 public constant performanceFeePercentage = 3000;
    uint256 public lastRecordedProfit;
    uint256 public totalProfits;

    constructor(address _vaultManagerAddr, address[] memory _initialAssets, address _owner) {
        _vaultManager = _vaultManagerAddr;
        _grantRole(VAULT_MANAGER_ROLE, _vaultManagerAddr);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        _admin = _owner;
        _setRoleAdmin(VAULT_MANAGER_ROLE, ADMIN_ROLE); // Admins can manage vault manager role
        for (uint256 i = 0; i < _initialAssets.length; i++) {
            supportedAssets.push(IERC20(_initialAssets[i]));
        }
        lastRecordedProfit = 0; // Initialize on contract creation
    }

    function setAssetToOracle(address _asset, address _oracle) external onlyRole(ADMIN_ROLE) {
        assetToOracle[_asset] = AggregatorV3Interface(_oracle);
    }

    // // Add a function to update performance fees and check for roles
    // function updatePerformanceFee(uint8 _newFee) external onlyRole(ADMIN_ROLE) {
    //     performanceFeePercentage = _newFee;
    // }

    function estimateVaultValue() public view returns (uint256) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            totalValue +=
                estimateAssetValue(address(supportedAssets[i]), totalVaultBalance[address(supportedAssets[i])]);
        }
        return totalValue;
    }

    function deposit(address _asset, uint256 _amount) external {
        require(isAssetSupported(IERC20(_asset)), "Asset not supported");
        IERC20(_asset).transferFrom(_msgSender(), address(this), _amount);
        totalVaultBalance[_asset] += _amount;
        userShares[_msgSender()].totalShares += estimateAssetValue(_asset, _amount);
        userShares[_msgSender()].assetShares[_asset] += _amount;
    }

    function withdrawProfits() external {
        uint256 profitShare = calculateUserProfitShare(_msgSender());
        // userProfits[_msgSender()] = 0;
        IERC20(address(supportedAssets[0])).transfer(_msgSender(), profitShare);
    }

    function withdraw(address _asset, uint256 _amount) external {
        require(userShares[_msgSender()].assetShares[_asset] >= _amount, "Insufficient balance");
        totalVaultBalance[_asset] -= _amount;

        // Proportional Profit Calculation (more on this below)
        uint256 profitShare = calculateUserProfitShare(_msgSender());
        // Distribute profits to user
        uint256 vaultShare = profitShare * performanceFeePercentage / 100;
        // Transfer Fees to the vault
        uint256 userShare = profitShare - vaultShare;

        uint256 currentAssetShares = userShares[_msgSender()].assetShares[_asset] - _amount;
        // Update user deposit records accordingly
        userShares[_msgSender()].totalShares -= estimateAssetValue(_asset, currentAssetShares);
        userShares[_msgSender()].assetShares[_asset] = currentAssetShares;

        IERC20(_asset).transfer(_admin, vaultShare);
        IERC20(_asset).transfer(_msgSender(), userShare);
    }

    function calculateUserProfitShare(address _user) internal view returns (uint256) {
        uint256 userShare = (userShares[_user].totalShares * 1e18) / estimateVaultValue();
        uint256 profitShare = (totalProfits * userShare) / 1e18;
        return profitShare;
    }

    function trade(address _asset1, uint256 _amount1, address _asset2) external onlyRole(VAULT_MANAGER_ROLE) {
        // Logic to execute the trade on Uniswap
        ITradingContract trader = IVaultManager(_vaultManager).getTraderContract();
        IERC20(_asset1).approve(address(trader), _amount1);
        // uint256 amountOut =
        trader.swapExactInputSingle(_asset1, _asset2, _amount1, address(this), performanceFeePercentage);

        // // Simplified profit estimation:
        // uint256 currentValue = estimateAssetValue(address(_asset2), amountOut); // Assuming you fetch the value of
        //     // received assets
        // uint256 previousValue = estimateAssetValue(address(_asset1), _amount1);
        // uint256 profit = currentValue - previousValue;
        // totalProfits += profit;
    }

    function isAssetSupported(IERC20 _asset) internal view returns (bool) {
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == _asset) {
                return true;
            }
        }
        return false;
    }

    function estimateAssetValue(address _asset, uint256 _amount) public view returns (uint256 valueUSD) {
        AggregatorV3Interface priceFeed = assetToOracle[_asset];
        require(priceFeed != AggregatorV3Interface(address(0)), "Oracle not set for asset");
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price data");
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 val = (_amount * uint256(price)) / (10 ** decimals);
        return val;
    }

    // Helper to calculate current price per share
    function currentPricePerShare(address asset) public view returns (uint256) {
        uint256 totalAssetValue = estimateAssetValue(asset, totalVaultBalance[asset]);
        uint256 totalShares = userShares[address(0)].assetShares[asset]; // Total shares for the asset
        return totalShares == 0 ? 1e18 : totalAssetValue / totalShares; // 1e18 is the initial share price
    }
}
