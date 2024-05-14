// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/src/Script.sol";
import { AssetVault } from "../src/AssetVault/AssetVault.sol";
import { VaultManager } from "../src/VaultManager/VaultManager.sol";

contract VaultScript is Script {
    VaultManager public manager;
    uint256 public deployerPrivateKey;
    uint256 public chainId;
    address public owner;

    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant WMATIC_USD = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
    address public constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address public constant USDC_USD = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address public constant SHIB = 0x6f8a06447Ff6FcF75d803135a7de15CE88C1d4ec;
    address public constant SHIB_USD = 0x3710abeb1A0Fc7C2EC59C26c8DAA7a448ff6125A;

    function run() public {
        // Private key of the deployer imported from the env.
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        chainId = vm.envUint("CHAIN_ID");
        // Address of the deployer.
        owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the VaultManager contract.
        manager = new VaultManager();
        address[] memory assets = new address[](3);
        assets[0] = WMATIC;
        assets[1] = USDC;
        assets[2] = SHIB;
        // Create a new vault.
        manager.createVault(assets);

        AssetVault vault = manager.managedVaults(0);

        IERC20(WMATIC).approve(address(vault), 10_000_000_000_000_000_000_000_000_000_000);
        IERC20(USDC).approve(address(vault), 10_000_000_000_000_000_000_000_000_000_000);
        IERC20(SHIB).approve(address(vault), 10_000_000_000_000_000_000_000_000_000_000);

        vault.setAssetToOracle(WMATIC, WMATIC_USD);
        vault.setAssetToOracle(USDC, USDC_USD);
        vault.setAssetToOracle(SHIB, SHIB_USD);

        vm.stopBroadcast();
    }
}
