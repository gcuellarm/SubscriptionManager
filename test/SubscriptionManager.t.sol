// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";

contract SubscriptionManagerTest is Test {
    SubscriptionManager internal manager;
    address internal provider = address(0xBEEF);
    address internal token = address(0xCAFE);

    function setUp() public {
        manager = new SubscriptionManager();
    }

    function test_CreatePlan() public {
        vm.prank(provider);
        uint256 planId = manager.createPlan(token, 10e6, 30 days);

        (
            address storedProvider,
            address storedToken,
            uint256 pricePerInterval,
            uint256 interval,
            bool active
        ) = manager.plans(planId);

        assertEq(storedProvider, provider);
        assertEq(storedToken, token);
        assertEq(pricePerInterval, 10e6);
        assertEq(interval, 30 days);
        assertTrue(active);
    }

    function test_Subscribe() public {
        vm.prank(provider);
        uint256 planId = manager.createPlan(token, 10e6, 30 days);

        address subscriber = address(0xABCD);
        vm.warp(1 days);
        vm.prank(subscriber);
        manager.subscribe(planId);

        uint8 status = uint8(manager.getSubscriptionStatus(planId, subscriber));
        assertEq(status, uint8(SubscriptionManager.SubscriptionStatus.ACTIVE));
    }
}
