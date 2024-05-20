// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IAssetVault } from "./IAssetVault.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

contract AssetVault is AccessControl, IAssetVault {
    using SafeERC20 for IERC20;

    event AssetDeposited(address indexed asset, uint256 amount);
    event AssetTraded(address indexed asset1, uint256 amount1, address indexed asset2, uint256 amount2);
    event AssetWithdrawn(address indexed asset, uint256 amount, address indexed user);
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
        _vaultManager = _owner;
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

    function setVaultManager(address _vaultManagerAddr) external onlyRole(ADMIN_ROLE) {
        _vaultManager = _vaultManagerAddr;
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
        // Balance or not
        require(isAssetSupported(IERC20(_asset)), "Asset not supported");
        IERC20(_asset).transferFrom(_msgSender(), address(this), _amount);
        vaultBalance[_asset] += _amount;
        uint256 points = estimateAssetValue(_asset, _amount);
        user[_msgSender()].points += points;
        totalPoints += points;
    }

    function withdraw(address _asset) external {
        require(isAssetSupported(IERC20(_asset)), "Asset not supported");
        uint256 userPoints = user[_msgSender()].points;
        require(userPoints > 0, "Insufficient points");

        uint256 totalVaultValue = estimateVaultValue();
        require(totalVaultValue > 0, "Vault value is zero");

        // Calculate the share value in USD that the user's points represent
        uint256 userShareValue = (userPoints * totalVaultValue) / totalPoints;

        uint256 assetAmountToWithdraw = estimateAssetAmount(_asset, userShareValue);
        require(vaultBalance[_asset] >= assetAmountToWithdraw, "Insufficient asset balance");

        // Adjust points and vault balance
        user[_msgSender()].points -= userPoints;
        vaultBalance[_asset] -= assetAmountToWithdraw;

        // Calculate profit fee and adjust withdrawal amount
        uint256 profitFeeAmount = (profitFee * assetAmountToWithdraw) / 100;
        assetAmountToWithdraw -= profitFeeAmount;

        // Transfer profit fee to the vault manager
        IERC20(_asset).safeTransfer(_vaultManager, profitFeeAmount);

        // Transfer the remaining asset amount to the user
        IERC20(_asset).safeTransfer(_msgSender(), assetAmountToWithdraw);

        totalPoints -= userPoints; // Adjust total points after withdrawal
        emit AssetWithdrawn(_asset, assetAmountToWithdraw, _msgSender());
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
        TransferHelper.safeApprove(_asset1, address(ROUTER), _amount1);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _asset1,
            tokenOut: _asset2,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount1,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 amountOut = ROUTER.exactInputSingle(params);
        require(amountOut > 0, "Trade failed or no output tokens");
        emit AssetTraded(_asset1, _amount1, _asset2, amountOut);

        // Recalculate points based on the new asset values
        adjustPointsAfterTrade(_asset1, _amount1, _asset2, amountOut);
    }

    function adjustPointsAfterTrade(address asset1, uint256 amount1, address asset2, uint256 amountOut) internal {
        uint256 asset1PointsBefore = estimateAssetValue(asset1, amount1);
        uint256 asset2PointsAfter = estimateAssetValue(asset2, amountOut);
        vaultBalance[asset1] -= amount1;
        vaultBalance[asset2] += amountOut;

        if (asset2PointsAfter > asset1PointsBefore) {
            uint256 pointsToAdd = asset2PointsAfter - asset1PointsBefore;
            totalPoints += pointsToAdd;
        } else {
            uint256 pointsToSubtract = asset1PointsBefore - asset2PointsAfter;
            require(totalPoints >= pointsToSubtract, "Total points underflow");
            totalPoints -= pointsToSubtract;
        }
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
