// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { AssetVault } from "../AssetVault/AssetVault.sol";
import { IVaultManager } from "./IVaultManager.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract VaultManager is AccessControl, IVaultManager {
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    AssetVault[] public managedVaults;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender()); // Deployer gets admin role
        _setRoleAdmin(TRADER_ROLE, ADMIN_ROLE); // Admins can manage trader role
    }

    function createVault(address[] memory _initialAssets, uint8 _performanceFee) external onlyRole(ADMIN_ROLE) {
        AssetVault newVault = new AssetVault(address(this), _initialAssets, _performanceFee, _msgSender());
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
        address _asset2,
        uint256 _amount2
    )
        external
        onlyRole(TRADER_ROLE)
    {
        AssetVault vault = managedVaults[_vaultIndex];
        vault.trade(_asset1, _amount1, _asset2, _amount2);
    }
}
