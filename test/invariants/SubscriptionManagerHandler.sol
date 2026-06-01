// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract SubscriptionManagerHandler is Test {
    SubscriptionManager public manager;
    MockERC20 public token;

    address[] public providers;
    address[] public subscribers;

    bool public reactivatedInactivePlan;

    uint256 public constant PRICE = 10e6;
    uint256 public constant INTERVAL = 30 days;

    constructor(SubscriptionManager _manager, MockERC20 _token) {
        manager = _manager;
        token = _token;

        providers.push(address(0xBEEF));
        providers.push(address(0xFACE));
        providers.push(address(0xCAFE));

        subscribers.push(address(0xDEAD));
        subscribers.push(address(0xAAAA));
        subscribers.push(address(0xBBBB));
    }

    /*//////////////////////////////////////////////////////////////
                                PLAN ACTIONS
    //////////////////////////////////////////////////////////////*/

    function createPlan(uint256 providerSeed) external {
        address provider = providers[providerSeed % providers.length];

        vm.prank(provider);
        manager.createPlan(
            address(token),
            PRICE,
            INTERVAL,
            "metadataURI"
        );
    }

    function deactivatePlan(uint256 providerSeed, uint256 planSeed) external {
        uint256 totalPlans = manager.nextPlanId();

        if (totalPlans == 0) return;

        uint256 planId = (planSeed % totalPlans) + 1;
        address provider = providers[providerSeed % providers.length];

        vm.prank(provider);

        try manager.deactivatePlan(planId) {
            // success
        } catch {
            // Expected reverts are ignored:
            // - InvalidPlan
            // - Unauthorized
            // - PlanAlreadyInactive
        }
    }

    function activatePlan(uint256 providerSeed, uint256 planSeed) external {
        uint256 totalPlans = manager.nextPlanId();

        if (totalPlans == 0) return;

        uint256 planId = (planSeed % totalPlans) + 1;
        address provider = providers[providerSeed % providers.length];

        vm.prank(provider);

        try manager.activatePlan(planId) {
            // success
        } catch {
            // Expected reverts are ignored:
            // - InvalidPlan
            // - Unauthorized
            // - PlanAlreadyActive
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SUBSCRIPTION ACTIONS
    //////////////////////////////////////////////////////////////*/

    function subscribe(uint256 subscriberSeed, uint256 planSeed) external {
        uint256 totalPlans = manager.nextPlanId();

        if (totalPlans == 0) return;

        uint256 planId = (planSeed % totalPlans) + 1;
        address subscriber = subscribers[subscriberSeed % subscribers.length];

        token.mint(subscriber, PRICE * 10);

        vm.prank(subscriber);
        token.approve(address(manager), PRICE * 10);

        vm.prank(subscriber);

        try manager.subscribe(planId) {
            // success
        } catch {
            // Expected reverts are ignored:
            // - InvalidPlan
            // - PlanInactive
            // - AlreadySubscribed
            // - ERC20 allowance/balance related reverts
        }
    }

    function cancelSubscription(
        uint256 subscriberSeed,
        uint256 subscriptionSeed
    ) external {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        if (totalSubscriptions == 0) return;

        uint256 subscriptionId = (subscriptionSeed % totalSubscriptions) + 1;
        address subscriber = subscribers[subscriberSeed % subscribers.length];

        vm.prank(subscriber);

        try manager.cancelSubscription(subscriptionId) {
            // success
        } catch {
            // Expected reverts are ignored:
            // - InvalidSubscription
            // - SubscriptionNotActive
            // - Unauthorized
        }
    }

    function cancelPastDueSubscription(uint256 subscriptionSeed) external {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        if (totalSubscriptions == 0) return;

        uint256 subscriptionId = (subscriptionSeed % totalSubscriptions) + 1;
        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        if (
            subscription.status !=
            SubscriptionManager.SubscriptionStatus.PAST_DUE
        ) return;

        vm.prank(subscription.subscriber);
        manager.cancelSubscription(subscriptionId);
    }

    function charge(uint256 providerSeed, uint256 subscriptionSeed) external {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        if (totalSubscriptions == 0) return;

        uint256 subscriptionId = (subscriptionSeed % totalSubscriptions) + 1;
        address provider = providers[providerSeed % providers.length];

        SubscriptionManager.Subscription memory subscription;

        try manager.getSubscription(subscriptionId) returns (
            SubscriptionManager.Subscription memory fetchedSubscription
        ) {
            subscription = fetchedSubscription;
        } catch {
            return;
        }

        if (block.timestamp < subscription.nextPaymentDue) {
            vm.warp(subscription.nextPaymentDue);
        }

        vm.prank(provider);

        try manager.charge(subscriptionId) {
            // success
        } catch {
            // Expected reverts are ignored:
            // - InvalidSubscription
            // - SubscriptionNotActive
            // - Unauthorized
            // - ChargeNotDue
            // - ERC20 allowance/balance related reverts
        }
    }

    function markPastDue(
        uint256 providerSeed,
        uint256 subscriptionSeed
    ) external {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        if (totalSubscriptions == 0) return;

        uint256 subscriptionId = (subscriptionSeed % totalSubscriptions) + 1;
        address provider = providers[providerSeed % providers.length];

        SubscriptionManager.Subscription memory subscription;

        try manager.getSubscription(subscriptionId) returns (
            SubscriptionManager.Subscription memory fetchedSubscription
        ) {
            subscription = fetchedSubscription;
        } catch {
            return;
        }

        if (block.timestamp < subscription.nextPaymentDue) {
            vm.warp(subscription.nextPaymentDue);
        }

        vm.prank(provider);

        try manager.markPastDue(subscriptionId) {
            // success
        } catch {
            // Expected reverts are ignored:
            // - InvalidSubscription
            // - SubscriptionNotActive
            // - Unauthorized
            // - ChargeNotDue
        }
    }

    function reactivatePastDueSubscription(
        uint256 subscriberSeed,
        uint256 subscriptionSeed
    ) external {
        uint256 totalSubscriptions = manager.nextSubscriptionId();

        if (totalSubscriptions == 0) return;

        uint256 subscriptionId = (subscriptionSeed % totalSubscriptions) + 1;
        address subscriber = subscribers[subscriberSeed % subscribers.length];
        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        token.mint(subscriber, PRICE * 10);

        vm.prank(subscriber);
        token.approve(address(manager), PRICE * 10);

        SubscriptionManager.Plan memory plan =
            manager.getPlan(subscription.planId);

        vm.prank(subscriber);

        try manager.reactivatePastDueSubscription(subscriptionId) {
            if (!plan.active) reactivatedInactivePlan = true;
        } catch {
            // Expected reverts are ignored:
            // - InvalidSubscription
            // - SubscriptionNotPastDue
            // - Unauthorized
            // - ERC20 allowance/balance related reverts
        }
    }
}
