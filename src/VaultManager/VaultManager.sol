// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { AssetVault } from "../AssetVault/AssetVault.sol";
import { IVaultManager } from "./IVaultManager.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { TradingContract } from "../Trade/Trade.sol";
import { ITradingContract } from "../Trade/ITrade.sol";



contract VaultManager is AccessControl, IVaultManager {
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    ITradingContract public tradingContract;
    
    AssetVault[] public managedVaults;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender()); // Deployer gets admin role
        _grantRole(ADMIN_ROLE, _msgSender()); // Deployer gets admin role
        _setRoleAdmin(TRADER_ROLE, ADMIN_ROLE); // Admins can manage trader role
        // 0xfff9976782d46cc05630d1f6ebab18b2324d6b14
        TradingContract trader = new TradingContract();
        tradingContract = ITradingContract(address(trader));
    }

    function getTraderContract() external view returns (ITradingContract) {
        return tradingContract;
    }

    function createVault(address[] memory _initialAssets) external onlyRole(ADMIN_ROLE) {
        AssetVault newVault = new AssetVault(address(this), _initialAssets, _msgSender());
        managedVaults.push(newVault);
    }

    function addTrader(address _trader) external onlyRole(ADMIN_ROLE) {
        _grantRole(TRADER_ROLE, _trader);
    }

    function removeTrader(address _trader) external onlyRole(ADMIN_ROLE) {
        revokeRole(TRADER_ROLE, _trader);
    }

    function executeTrade(
        uint256 _vaultIndex,
        address _asset1,
        uint256 _amount1,
        address _asset2
    )
        external
        onlyRole(TRADER_ROLE)
    {
        AssetVault vault = managedVaults[_vaultIndex];
        vault.trade(_asset1, _amount1, _asset2);
    }
}
