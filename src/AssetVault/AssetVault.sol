// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ITradingContract } from "../Trade/ITrade.sol";
import { IVaultManager } from "../VaultManager/IVaultManager.sol";
import { IAssetVault } from "./IAssetVault.sol";

contract AssetVault is AccessControl, IAssetVault {
    struct UserPoints {
        uint256 points;
    }

    mapping(address => UserPoints) public user;

    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IERC20[] public supportedAssets;
    mapping(address => uint256) public vaultBalance;
    mapping(address => AggregatorV3Interface) assetToOracle; // Store oracle addresses

    address private _admin;
    address private _vaultManager;
    uint24 public poolFee = 3000;
    uint24 public profitFee = 10;
    uint256 public totalPoints;

    constructor(address _vaultManagerAddr, address[] memory _initialAssets, address _owner) {
        _vaultManager = _vaultManagerAddr;
        _grantRole(VAULT_MANAGER_ROLE, _owner);
        _grantRole(VAULT_MANAGER_ROLE, _vaultManagerAddr);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        _admin = _owner;
        _setRoleAdmin(VAULT_MANAGER_ROLE, ADMIN_ROLE); // Admins can manage vault manager role
        for (uint256 i = 0; i < _initialAssets.length; i++) {
            supportedAssets.push(IERC20(_initialAssets[i]));
        }
    }

    function setAssetToOracle(address _asset, address _oracle) external onlyRole(ADMIN_ROLE) {
        assetToOracle[_asset] = AggregatorV3Interface(_oracle);
    }

    // // Add a function to update pool fee and check for roles
    function updatePoolFee(uint8 _newPoolFee) external onlyRole(ADMIN_ROLE) {
        poolFee = _newPoolFee;
    }

    function updateProfitFee(uint8 _newProfitFee) external onlyRole(ADMIN_ROLE) {
        profitFee = _newProfitFee;
    }

    function estimateVaultValue() public view returns (uint256) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            totalValue += estimateAssetValue(address(supportedAssets[i]), vaultBalance[address(supportedAssets[i])]);
        }
        return totalValue;
    }

    function deposit(address _asset, uint256 _amount) external {
        require(isAssetSupported(IERC20(_asset)), "Asset not supported");
        IERC20(_asset).transferFrom(_msgSender(), address(this), _amount);
        vaultBalance[_asset] += _amount;
        uint256 points = estimateAssetValue(_asset, _amount);
        user[_msgSender()].points += points;
        totalPoints += points;
    }

    function withdraw(address _asset) external {
        require(isAssetSupported(IERC20(_asset)), "Asset not supported");
        uint256 requestPoints = user[_msgSender()].points;
        require(requestPoints > 0, "Insufficient points");

        uint256 vaultValue = estimateVaultValue();
        (, uint256 perPointValue) = Math.tryDiv(vaultValue, totalPoints);
        uint256 shareValue = pointsValueInUSD(requestPoints);
        require(shareValue > 0, "Share value must be greater than zero");

        uint256 userShare = estimateAssetAmount(_asset, shareValue);
        uint256 availableBalance = vaultBalance[_asset];
        if (userShare > availableBalance) {
            userShare = availableBalance;
        }

        vaultBalance[_asset] -= userShare;
        uint256 deductedValue = estimateAssetValue(_asset, userShare);
        (, uint256 deductedPoints) = Math.tryDiv(estimateAssetValue(_asset, deductedValue), perPointValue);
        user[_msgSender()].points -= deductedPoints;

        uint256 vaultShare = 0;
        (bool success, uint256 profit) = Math.trySub(deductedValue, deductedPoints);
        if (success) {
            uint256 profitShare = (profit * userShare) / deductedValue;
            vaultShare = (profitFee * profitShare) / 100;
            userShare -= vaultShare;
        }

        if (vaultShare > 0) {
            IERC20(_asset).transfer(_vaultManager, vaultShare);
        }
        IERC20(_asset).transfer(_msgSender(), userShare);
    }

    function calculateUserProfitShare(address _user) internal view returns (uint256) {
        uint256 requestPoints = user[_user].points;
        uint256 shareValue = pointsValueInUSD(requestPoints);
        (, uint256 profit) = Math.trySub(shareValue, requestPoints);
        return profit;
    }

    function trade(address _asset1, uint256 _amount1, address _asset2) external onlyRole(VAULT_MANAGER_ROLE) {
        require(_asset1 != address(0) && _asset2 != address(0), "Asset addresses cannot be zero");
        require(_amount1 > 0, "Trade amount must be positive");

        // Ensure there is enough balance to trade
        require(vaultBalance[_asset1] >= _amount1, "Insufficient asset1 balance");

        // Get current balances before the trade
        uint256 asset1Points = estimateAssetValue(_asset1, _amount1);

        // Logic to execute the trade on Uniswap
        ITradingContract trader = IVaultManager(_vaultManager).getTraderContract();
        IERC20(_asset1).approve(address(trader), _amount1);
        uint256 amountOut = trader.swapExactInputSingle(_asset1, _asset2, _amount1, address(this), poolFee);
        require(amountOut > 0, "Trade failed or no output tokens");

        uint256 asset2Points = estimateAssetValue(_asset2, amountOut);

        // Update points safely checking for underflows and overflows
        if (asset2Points > asset1Points) {
            uint256 pointsToAdd = asset2Points - asset1Points;
            totalPoints += pointsToAdd;
        } else {
            uint256 pointsToSubtract = asset1Points - asset2Points;
            require(totalPoints >= pointsToSubtract, "Total points underflow");
            totalPoints -= pointsToSubtract;
        }

        // Update vault balances safely
        vaultBalance[_asset1] -= _amount1;
        vaultBalance[_asset2] += amountOut;
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

    function estimateAssetAmount(address _asset, uint256 _valueUSD) public view returns (uint256 amount) {
        AggregatorV3Interface priceFeed = assetToOracle[_asset];
        require(priceFeed != AggregatorV3Interface(address(0)), "Oracle not set for asset");
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price data");
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 val = (_valueUSD * (10 ** decimals)) / uint256(price);
        return val;
    }

    function pointsValueInUSD(uint256 points) public view returns (uint256) {
        (, uint256 usdValue) = Math.tryDiv((points * estimateVaultValue()), totalPoints);
        return usdValue;
    }

    function estimateAssetValueInUSD(address _asset) public view returns (uint256 total, uint256 valueInUsd) {
        uint256 value = estimateAssetValue(_asset, vaultBalance[_asset]);
        return (vaultBalance[_asset], value);
    }

    function emergencyWithdrawAll() external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            IERC20 asset = supportedAssets[i];
            uint256 balance = vaultBalance[address(asset)];
            if (balance > 0) {
                vaultBalance[address(asset)] = 0;
                IERC20(address(asset)).transfer(_admin, balance);
            }
        }
    }
}
