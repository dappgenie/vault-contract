// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.25;

import { Script } from "forge-std/src/Script.sol";
import { VaultManager } from "../src/VaultManager/VaultManager.sol";

contract VaultScript is Script {
    VaultManager public manager;
    uint256 public deployerPrivateKey;
    uint256 public chainId;
    address public owner;
    // address constant public swapRouter = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    function run() public {
        // Private key of the deployer imported from the env.
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        chainId = vm.envUint("CHAIN_ID");
        // Address of the deployer.
        owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the VaultManager contract.
        manager = new VaultManager();
        vm.stopBroadcast();
    }
}
