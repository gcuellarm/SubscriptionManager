// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";

contract SubscriptionManagerScript is Script {
    function run() external {
        vm.startBroadcast();
        new SubscriptionManager();
        vm.stopBroadcast();
    }
}
