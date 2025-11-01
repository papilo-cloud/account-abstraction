// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMinimal is Script {
    function run() public {

    }

    function deploy() public returns (HelperConfig, MinimalAccount) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        MinimalAccount minAccount = new MinimalAccount(config.entryPoint);
        minAccount.transferOwnership(config.account);
        vm.stopBroadcast();
        return (helperConfig, minAccount);
    }
    
}