// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {SubscriptionManagerHandler} from "./SubscriptionManagerHandler.sol";

contract SubscriptionManagerInvariantTest is StdInvariant, Test {
    SubscriptionManager public manager;
    MockERC20 public token;
    SubscriptionManagerHandler public handler;

    address internal treasury = address(0x9999);
    uint256 public constant PROTOCOL_FEE_BPS = 100;

    function setUp() public {
        manager = new SubscriptionManager(treasury, PROTOCOL_FEE_BPS);
        token = new MockERC20("Mock USDC", "mUSDC", 6);

        handler = new SubscriptionManagerHandler(manager, token);

        targetContract(address(handler));
    }

    function invariant_CreatedSubscriptionsHaveValidNextPaymentDue() public view {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        for (uint256 i = 1; i <= totalSubscriptions; i++) {
            SubscriptionManager.Subscription memory subscription =
                manager.getSubscription(i);

            assertGt(subscription.nextPaymentDue, 0);
        }
    }

    function invariant_CancelledSubscriptionsAreNotRegisteredInSubscriptionOf() public view {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        for (uint256 i = 1; i <= totalSubscriptions; i++) {
            SubscriptionManager.Subscription memory subscription =
                manager.getSubscription(i);

            if (
                subscription.status ==
                SubscriptionManager.SubscriptionStatus.CANCELLED
            ) {
                uint256 registeredSubscriptionId =
                    manager.getSubscriptionOf(
                        subscription.planId,
                        subscription.subscriber
                    );

                assertTrue(registeredSubscriptionId != i);
            }
        }
    }

    function invariant_ActiveSubscriptionsAreRegisteredInSubscriptionOf() public view {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        for (uint256 i = 1; i <= totalSubscriptions; i++) {
            SubscriptionManager.Subscription memory subscription =
                manager.getSubscription(i);

            if (
                subscription.status ==
                SubscriptionManager.SubscriptionStatus.ACTIVE
            ) {
                uint256 registeredSubscriptionId =
                    manager.getSubscriptionOf(
                        subscription.planId,
                        subscription.subscriber
                    );

                assertEq(registeredSubscriptionId, i);
            }
        }
    }

    function invariant_NoSubscriptionHasNoneStatusAfterCreation() public view {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        for (uint256 i = 1; i <= totalSubscriptions; i++) {
            SubscriptionManager.Subscription memory subscription =
                manager.getSubscription(i);

            assertTrue(
                subscription.status !=
                    SubscriptionManager.SubscriptionStatus.NONE
            );
        }
    }

    function invariant_PastDueSubscriptionsCannotReactivateWhilePlanIsInactive() public view {
        assertFalse(handler.reactivatedInactivePlan());
    }
}
