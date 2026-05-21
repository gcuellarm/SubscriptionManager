// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";

contract SubscriptionManagerScript is Script {
    uint256 constant DEFAULT_PROTOCOL_FEE_BPS = 100; // 1%

    function run() external {
        address treasury = vm.envAddress("TREASURY");
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", DEFAULT_PROTOCOL_FEE_BPS);

        vm.startBroadcast();
        new SubscriptionManager(treasury, protocolFeeBps);
        vm.stopBroadcast();
    }
}
