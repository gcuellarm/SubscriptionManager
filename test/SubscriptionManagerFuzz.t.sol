// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SubscriptionManagerFuzzTest is Test {
    SubscriptionManager public manager;
    MockERC20 public mockToken;

    address internal provider = address(0xBEEF);
    address internal subscriber = address(0xDEAD);
    address internal treasury = address(0xCAFE);

    uint256 public constant BPS = 10_000;
    uint256 public constant PROTOCOL_FEE_BPS = 100;

    function setUp() public {
        manager = new SubscriptionManager(treasury, PROTOCOL_FEE_BPS);
        mockToken = new MockERC20("Mock USDC", "mUSDC", 6);
    }

    function _feeAmount(uint256 amount) internal pure returns (uint256) {
        return (amount * PROTOCOL_FEE_BPS) / BPS;
    }

    function _providerAmount(uint256 amount) internal pure returns (uint256) {
        return amount - _feeAmount(amount);
    }

    function testFuzz_CreatePlanStoresCorrectData(
        uint256 price,
        uint256 interval
    ) public {
        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);

        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        SubscriptionManager.Plan memory plan = manager.getPlan(planId);

        assertEq(planId, 1);
        assertEq(plan.provider, provider);
        assertEq(plan.token, address(mockToken));
        assertEq(plan.pricePerInterval, price);
        assertEq(plan.interval, interval);
        assertEq(plan.metadataURI, "metadataURI");
        assertTrue(plan.active);
    }

    function testFuzz_CreatePlanWithDifferentProviders(
        address fuzzProvider,
        uint256 price,
        uint256 interval
    ) public {
        vm.assume(fuzzProvider != address(0));
        vm.assume(fuzzProvider != address(manager));

        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(fuzzProvider);

        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        SubscriptionManager.Plan memory plan = manager.getPlan(planId);

        assertEq(plan.provider, fuzzProvider);
        assertEq(plan.pricePerInterval, price);
        assertEq(plan.interval, interval);
    }

    function testFuzz_SubscribeWithDifferentPrices(
        uint256 price,
        uint256 interval
    ) public {
        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);
        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        mockToken.mint(subscriber, price);

        vm.prank(subscriber);
        mockToken.approve(address(manager), price);

        uint256 expectedNextPaymentDue = block.timestamp + interval;

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        assertEq(subscription.planId, planId);
        assertEq(subscription.subscriber, subscriber);
        assertEq(subscription.nextPaymentDue, expectedNextPaymentDue);

        assertEq(mockToken.balanceOf(provider), _providerAmount(price));
        assertEq(mockToken.balanceOf(treasury), _feeAmount(price));
        assertEq(mockToken.balanceOf(subscriber), 0);
    }

    function testFuzz_ChargeUpdatesNextPaymentDue(
        uint256 price,
        uint256 interval
    ) public {
        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);
        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        mockToken.mint(subscriber, price * 2);

        vm.prank(subscriber);
        mockToken.approve(address(manager), price * 2);

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscriptionBefore =
            manager.getSubscription(subscriptionId);

        vm.warp(subscriptionBefore.nextPaymentDue);

        vm.prank(provider);
        manager.charge(subscriptionId);

        SubscriptionManager.Subscription memory subscriptionAfter =
            manager.getSubscription(subscriptionId);

        assertEq(
            subscriptionAfter.nextPaymentDue,
            subscriptionBefore.nextPaymentDue + interval
        );

        assertEq(
            uint256(subscriptionAfter.status),
            uint256(SubscriptionManager.SubscriptionStatus.ACTIVE)
        );
    }

    function testFuzz_ReactivatePastDueSubscription(
        uint256 price,
        uint256 interval
    ) public {
        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);
        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        mockToken.mint(subscriber, price * 2);

        vm.prank(subscriber);
        mockToken.approve(address(manager), price * 2);

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscriptionBefore =
            manager.getSubscription(subscriptionId);

        vm.warp(subscriptionBefore.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);

        vm.prank(subscriber);
        manager.reactivatePastDueSubscription(subscriptionId);

        SubscriptionManager.Subscription memory subscriptionAfter =
            manager.getSubscription(subscriptionId);

        assertEq(
            uint256(subscriptionAfter.status),
            uint256(SubscriptionManager.SubscriptionStatus.ACTIVE)
        );

        assertEq(
            subscriptionAfter.nextPaymentDue,
            subscriptionBefore.nextPaymentDue + interval
        );
    }

    function testFuzz_CancelPastDueSubscriptionClearsRegistration(
        uint256 price,
        uint256 interval
    ) public {
        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);
        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        mockToken.mint(subscriber, price);

        vm.prank(subscriber);
        mockToken.approve(address(manager), price);

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);

        SubscriptionManager.Subscription memory cancelledSubscription =
            manager.getSubscription(subscriptionId);

        assertEq(
            uint256(cancelledSubscription.status),
            uint256(SubscriptionManager.SubscriptionStatus.CANCELLED)
        );
        assertEq(manager.getSubscriptionOf(planId, subscriber), 0);
    }

    function testFuzz_RevertIf_ReactivatePastDueSubscriptionWithInactivePlan(
        uint256 price,
        uint256 interval
    ) public {
        price = bound(price, 1, 1_000_000e6);
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);
        uint256 planId = manager.createPlan(
            address(mockToken),
            price,
            interval,
            "metadataURI"
        );

        mockToken.mint(subscriber, price * 2);

        vm.prank(subscriber);
        mockToken.approve(address(manager), price * 2);

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.startPrank(provider);
        manager.markPastDue(subscriptionId);
        manager.deactivatePlan(planId);
        vm.stopPrank();

        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.PlanInactive.selector);

        manager.reactivatePastDueSubscription(subscriptionId);
    }

    function testFuzz_ConstructorAcceptsValidFees(uint256 feeBps) public {
        feeBps = bound(feeBps, 0, BPS);

        SubscriptionManager newManager =
            new SubscriptionManager(treasury, feeBps);

        assertEq(newManager.treasury(), treasury);
        assertEq(newManager.protocolFeeBps(), feeBps);
    }

    function testFuzz_RevertIf_ConstructorFeeTooHigh(
        uint256 feeBps
    ) public {
        feeBps = bound(feeBps, BPS + 1, type(uint16).max);

        vm.expectRevert(SubscriptionManager.InvalidFee.selector);

        new SubscriptionManager(treasury, feeBps);
    }

    function testFuzz_RevertIf_CreatePlanWithZeroPrice(
        uint256 interval
    ) public {
        interval = bound(interval, 1 hours, 365 days);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.InvalidAmount.selector);

        manager.createPlan(
            address(mockToken),
            0,
            interval,
            "metadataURI"
        );
    }

    function testFuzz_RevertIf_CreatePlanWithZeroInterval(
        uint256 price
    ) public {
        price = bound(price, 1, 1_000_000e6);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.InvalidInterval.selector);

        manager.createPlan(
            address(mockToken),
            price,
            0,
            "metadataURI"
        );
    }
}
