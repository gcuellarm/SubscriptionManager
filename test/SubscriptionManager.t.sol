// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SubscriptionManagerTest is Test {
    SubscriptionManager public manager;
    MockERC20 public mockToken;

    address internal provider = address(0xBEEF);
    address internal anotherProvider = address(0xFACE);
    address internal subscriber = address(0xDEAD);
    address internal anotherSubscriber = address(0xAAAA);

    uint256 public constant PRICE = 10e6;
    uint256 public constant INTERVAL = 30 days;

    event PlanCreated(
        uint256 indexed planId,
        address indexed provider,
        address indexed token,
        uint256 pricePerInterval,
        uint256 interval,
        string metadataURI
    );

    event Subscribed(
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber,
        uint256 nextPaymentDue
    );

    event SubscriptionCharged(
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber,
        uint256 amount,
        uint256 nextPaymentDue
    );

    event SubscriptionCancelled(
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber
    );
    event PlanDeactivated(
        uint256 indexed planId,
        address indexed provider
    );

    event PlanActivated(
        uint256 indexed planId,
        address indexed provider
    );

    event SubscriptionMarkedPastDue(
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber,
        uint256 dueTimestamp
    );

    event SubscriptionReactivated(
        uint256 indexed subscriptionId,
        uint256 indexed planId,
        address indexed subscriber,
        uint256 amount,
        uint256 nextPaymentDue
    );

    function setUp() public {
        manager = new SubscriptionManager();
        mockToken = new MockERC20("Mock USDC", "mUSDC", 6);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createPlan() internal returns (uint256 planId) {
        vm.prank(provider);

        planId = manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI"
        );
    }

    function _fundAndApprove(address user, uint256 amount) internal {
        mockToken.mint(user, amount);

        vm.prank(user);
        mockToken.approve(address(manager), amount);
    }

    function _createPastDueSubscription() internal returns (uint256 subscriptionId) {
        subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);
    }

    function _createPastDueSubscriptionWithoutRemainingAllowance() internal returns (uint256 subscriptionId){
        uint256 planId = _createPlan();

        mockToken.mint(subscriber, PRICE);

        vm.prank(subscriber);
        mockToken.approve(address(manager), PRICE);

        vm.prank(subscriber);
        subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATE PLAN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreatePlanStoresCorrectData() public {
        vm.prank(provider);

        uint256 planId = manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI"
        );

        SubscriptionManager.Plan memory plan = manager.getPlan(planId);

        assertEq(planId, 1);
        assertEq(plan.provider, provider);
        assertEq(plan.token, address(mockToken));
        assertEq(plan.pricePerInterval, PRICE);
        assertEq(plan.interval, INTERVAL);
        assertEq(plan.metadataURI, "metadataURI");
        assertTrue(plan.active);
    }

    function test_CreatePlanEmitsEvent() public {
        vm.expectEmit(true, true, true, true);

        emit PlanCreated(
            1,
            provider,
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI"
        );

        vm.prank(provider);

        manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI"
        );
    }

    function test_RevertIf_TokenIsZero() public {
        vm.prank(provider);

        vm.expectRevert(SubscriptionManager.InvalidAddress.selector);

        manager.createPlan(
            address(0),
            PRICE,
            INTERVAL,
            "metadataURI"
        );
    }

    function test_RevertIf_PricePerIntervalIsZero() public {
        vm.prank(provider);

        vm.expectRevert(SubscriptionManager.InvalidAmount.selector);

        manager.createPlan(
            address(mockToken),
            0,
            INTERVAL,
            "metadataURI"
        );
    }

    function test_RevertIf_IntervalIsZero() public {
        vm.prank(provider);

        vm.expectRevert(SubscriptionManager.InvalidInterval.selector);

        manager.createPlan(
            address(mockToken),
            PRICE,
            0,
            "metadataURI"
        );
    }

    function test_MultiplePlansHaveIncrementalIds() public {
        vm.startPrank(provider);

        uint256 planId1 = manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI1"
        );

        uint256 planId2 = manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI2"
        );

        vm.stopPrank();

        assertEq(planId1, 1);
        assertEq(planId2, 2);
        assertEq(planId2, planId1 + 1);
        assertEq(manager.nextPlanId(), 2);
    }

    function test_DifferentProvidersCanCreatePlans() public {
        vm.prank(provider);

        uint256 planId1 = manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI1"
        );

        vm.prank(anotherProvider);

        uint256 planId2 = manager.createPlan(
            address(mockToken),
            PRICE,
            INTERVAL,
            "metadataURI2"
        );

        SubscriptionManager.Plan memory plan1 = manager.getPlan(planId1);
        SubscriptionManager.Plan memory plan2 = manager.getPlan(planId2);

        assertEq(planId1, 1);
        assertEq(planId2, 2);

        assertEq(plan1.provider, provider);
        assertEq(plan2.provider, anotherProvider);
    }

    function test_RevertIf_GetInvalidPlan() public {
        vm.expectRevert(SubscriptionManager.InvalidPlan.selector);

        manager.getPlan(1);
    }

// =============================================================================
// SUBSCRIBE FUNCTION TESTS
// =============================================================================

    function test_SubscribeStoresCorrectData() public{
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE);

        uint256 expectedNextPaymentDue = block.timestamp + INTERVAL;

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        assertEq(subscriptionId, 1);
        assertEq(subscription.planId, planId);
        assertEq(subscription.subscriber, subscriber);
        assertEq(subscription.nextPaymentDue, expectedNextPaymentDue);
        assertEq(uint256(subscription.status), uint256(SubscriptionManager.SubscriptionStatus.ACTIVE));
    }

    function test_SubscribeTransfersInitialPaymentToProvider() public{
        uint256 planId = _createPlan();
        _fundAndApprove(subscriber, PRICE);
        
        uint256 providerBalanceBefore = mockToken.balanceOf(provider);
        uint256 subscriberBalanceBefore = mockToken.balanceOf(subscriber);

        vm.prank(subscriber);
        manager.subscribe(planId);

        uint256 providerBalanceAfter = mockToken.balanceOf(provider);
        uint256 subscriberBalanceAfter = mockToken.balanceOf(subscriber);

        assertEq(providerBalanceAfter, providerBalanceBefore + PRICE);
        assertEq(subscriberBalanceAfter, subscriberBalanceBefore - PRICE);
    }

    function test_SubscribeEmitsEvent() public{
        uint256 planId = _createPlan();
        _fundAndApprove(subscriber, PRICE);
        uint256 expectedNextPaymentDue = block.timestamp + INTERVAL;

        vm.startPrank(subscriber);

        vm.expectEmit(true, true, true, true);
        emit Subscribed(
            1,
            planId,
            subscriber,
            expectedNextPaymentDue
        );

        manager.subscribe(planId);
        vm.stopPrank();
    }

    function test_RevertIf_SubscribeToInvalidPlan() public {
        uint256 invalidPlanId = 999;
        
        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.InvalidPlan.selector);

        manager.subscribe(invalidPlanId);
    }

// user has funds but reverts because he has not done approve(address(manager), PRICE) yet
    function test_RevertIf_SubscribeWithoutApproval() public {
        uint256 planId = _createPlan();

        mockToken.mint(subscriber, PRICE);
        
        vm.prank(subscriber);
        vm.expectRevert();
        
        manager.subscribe(planId);
    }

    function test_RevertIf_SubscribeWithoutEnoughBalance() public {
        uint256 planId = _createPlan();

        vm.prank(subscriber);
        mockToken.approve(address(manager), PRICE);
        
        vm.prank(subscriber);
        vm.expectRevert();
        
        manager.subscribe(planId);
    }

    function test_MultipleUsersCanSubscribeSamePlan() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE);
        _fundAndApprove(anotherSubscriber, PRICE);

        vm.prank(subscriber);
        uint256 subscriptionId1 = manager.subscribe(planId);

        vm.prank(anotherSubscriber);
        uint256 subscriptionId2 = manager.subscribe(planId);

        SubscriptionManager.Subscription memory subscription1 = manager.getSubscription(subscriptionId1);
        SubscriptionManager.Subscription memory subscription2 = manager.getSubscription(subscriptionId2);

        assertEq(subscriptionId1, 1);
        assertEq(subscriptionId2, 2);

        assertEq(subscription1.planId, planId);
        assertEq(subscription2.planId, planId);

        assertEq(subscription1.subscriber, subscriber);
        assertEq(subscription2.subscriber, anotherSubscriber);

        assertEq(uint256(subscription1.status), uint256(SubscriptionManager.SubscriptionStatus.ACTIVE));
        assertEq(uint256(subscription2.status), uint256(SubscriptionManager.SubscriptionStatus.ACTIVE));
    }

    function test_MultipleSubscriptionsHaveIncrementalIds() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE);
        _fundAndApprove(anotherSubscriber, PRICE);

        vm.prank(subscriber);
        uint256 subscriptionId1 = manager.subscribe(planId);

        vm.prank(anotherSubscriber);
        uint256 subscriptionId2 = manager.subscribe(planId);

        assertEq(subscriptionId1, 1);
        assertEq(subscriptionId2, 2);
        assertEq(manager.nextSubscriptionId(), 2);
    }

    function test_RevertIf_GetInvalidSubscription() public {
        vm.expectRevert(abi.encodeWithSelector(SubscriptionManager.InvalidSubscription.selector));
        manager.getSubscription(1);
    }

    function test_SubscribeConsumesAllowance() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE);

        assertEq(mockToken.allowance(subscriber, address(manager)), PRICE);

        vm.prank(subscriber);
        manager.subscribe(planId);

        assertEq(mockToken.allowance(subscriber, address(manager)), 0);
    }

    function test_MultipleSubscriptionsIncreaseProviderBalance() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE);
        _fundAndApprove(anotherSubscriber, PRICE);

        vm.prank(subscriber);
        manager.subscribe(planId);

        vm.prank(anotherSubscriber);
        manager.subscribe(planId);

        assertEq(mockToken.balanceOf(provider), PRICE * 2);
    }
    // =============================================================================
    // CHARGE FUNCTION TESTS
    // =============================================================================

    //charge function helper
    function _createSubscriptionWithBalanceAndAllowance(uint256 amount) internal returns (uint256 subscriptionId) {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, amount);

        vm.prank(subscriber);
        subscriptionId = manager.subscribe(planId);
    }

    function test_ChargeTransfersPaymentToProvider() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        uint256 providerBalanceBefore = mockToken.balanceOf(provider);
        uint256 subscriberBalanceBefore = mockToken.balanceOf(subscriber);

        vm.warp(block.timestamp + INTERVAL);

        vm.prank(provider);
        manager.charge(subscriptionId);

        assertEq(mockToken.balanceOf(provider), providerBalanceBefore + PRICE);
        assertEq(mockToken.balanceOf(subscriber), subscriberBalanceBefore - PRICE);
    }

    function test_ChargeUpdatesNextPaymentDue() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscriptionBefore = manager.getSubscription(subscriptionId);

        uint256 expectedNextPaymentDue = subscriptionBefore.nextPaymentDue + INTERVAL;
        
        vm.warp(subscriptionBefore.nextPaymentDue);

        vm.prank(provider);
        manager.charge(subscriptionId);

        SubscriptionManager.Subscription memory subscriptionAfter = manager.getSubscription(subscriptionId);
        assertEq(subscriptionAfter.nextPaymentDue, expectedNextPaymentDue);
    }

    function test_ChargeEmitsEvent() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscriptionBefore = manager.getSubscription(subscriptionId);

        uint256 expectedNextPaymentDue = subscriptionBefore.nextPaymentDue + INTERVAL;
        
        vm.warp(subscriptionBefore.nextPaymentDue);

        vm.expectEmit(true, true, true, true);

        emit SubscriptionCharged(
            subscriptionId,
            subscriptionBefore.planId,
            subscriber,
            PRICE,
            expectedNextPaymentDue
        );

        vm.prank(provider);
        manager.charge(subscriptionId);
    }

    function test_RevertIf_ChargeInvalidSubscription() public {
        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.InvalidSubscription.selector);
        manager.charge(1);
    }

    function test_RevertIf_NonProviderCharges() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.warp(block.timestamp + INTERVAL);

        vm.prank(anotherProvider);
        vm.expectRevert(SubscriptionManager.Unauthorized.selector);

        manager.charge(subscriptionId);
    }

    function test_RevertIf_ChargeTooEarly() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);
        
        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.ChargeNotDue.selector);

        manager.charge(subscriptionId);
    }

    function test_RevertIf_ChargeWithoutAllowance() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE);

        vm.warp(block.timestamp + INTERVAL);
        
        vm.prank(provider);
        vm.expectRevert();

        manager.charge(subscriptionId);
    }

    function test_RevertIf_ChargeWithoutEnoughBalance() public {
        uint256 planId = _createPlan();

        mockToken.mint(subscriber, PRICE);

        vm.startPrank(subscriber);
        mockToken.approve(address(manager), PRICE * 2);
        uint256 subscriptionId = manager.subscribe(planId);
        
        vm.stopPrank();
        
        vm.warp(block.timestamp + INTERVAL);
        
        vm.prank(provider);
        vm.expectRevert();
        
        manager.charge(subscriptionId);
    }
    ////////////////////////////////////////////////////////
    // CANCEL SUBSCRIPTION TESTS
    ////////////////////////////////////////////////////////

    function test_CancelSubscriptionSetsInactive() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);
        
        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);
        assertEq(uint256(subscription.status), uint256(SubscriptionManager.SubscriptionStatus.CANCELLED));
    }

    function test_CancelSubscriptionEmitsEvent() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionCancelled(subscriptionId, subscription.planId, subscription.subscriber);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);
    }

    function test_RevertIf_CancelInvalidSubscription() public {
        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.InvalidSubscription.selector);
        manager.cancelSubscription(1);
    }

    function test_RevertIf_NonSubscriberCancels() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(anotherSubscriber);
        vm.expectRevert(SubscriptionManager.Unauthorized.selector);
        manager.cancelSubscription(subscriptionId);
    }

    function test_RevertIf_CancelAlreadyInactiveSubscription() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);

        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.SubscriptionNotActive.selector);
        manager.cancelSubscription(subscriptionId);
    }

    function test_RevertIf_ChargeCancelledSubscription() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);
        
        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.SubscriptionNotActive.selector);
        manager.charge(subscriptionId);
    }

    //////////////////////////////////////////////////
    // Plan Activation/Deactivation Tests
    //////////////////////////////////////////////////
    function test_DeactivatePlanSetsActiveFalse() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        manager.deactivatePlan(planId);

        SubscriptionManager.Plan memory plan = manager.getPlan(planId);
        assertEq(plan.active, false);
    }

    function test_DeactivatePlanEmitsEvent() public {
        uint256 planId = _createPlan();

        vm.expectEmit(true, true, false, true);
        emit PlanDeactivated(planId, provider);

        vm.prank(provider);
        manager.deactivatePlan(planId);
    }

    function test_ActivatePlanSetsActiveTrue() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        manager.deactivatePlan(planId);
        
        vm.prank(provider);
        manager.activatePlan(planId);
        
        SubscriptionManager.Plan memory plan = manager.getPlan(planId);

        assertTrue(plan.active);
    }

    function test_ActivatePlanEmitsEvent() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        manager.deactivatePlan(planId);

        vm.expectEmit(true, true, false, true);
        emit PlanActivated(planId, provider);

        vm.prank(provider);
        manager.activatePlan(planId);
    }

    function test_RevertIf_NonProviderDeactivatesPlan() public {
        uint256 planId = _createPlan();

        vm.prank(anotherProvider);
        vm.expectRevert(SubscriptionManager.Unauthorized.selector);

        manager.deactivatePlan(planId);
    }

    function test_RevertIf_NonProviderActivatesPlan() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        manager.deactivatePlan(planId);

        vm.prank(anotherProvider);
        vm.expectRevert(SubscriptionManager.Unauthorized.selector);
        
        manager.activatePlan(planId);
    }

    function test_RevertIf_DeactivateInvalidPlan() public {
        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.InvalidPlan.selector);
        
        manager.deactivatePlan(1);
    }

    function test_RevertIf_ActivateInvalidPlan() public {
        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.InvalidPlan.selector);

        manager.activatePlan(999);
    }

    function test_RevertIf_SubscribeToInactivePlan() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        manager.deactivatePlan(planId);

        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.PlanInactive.selector);
        
        manager.subscribe(planId);
    }

    function test_ExistingSubscriptionCanStillBeChargedAfterPlanDeactivation() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(provider);
        manager.deactivatePlan(subscriptionId);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);
        
        vm.warp(subscription.nextPaymentDue);

        uint256 providerBalanceBefore = mockToken.balanceOf(provider);
        vm.prank(provider);
        manager.charge(subscriptionId);

        assertEq(mockToken.balanceOf(provider), providerBalanceBefore + PRICE);
    }

    function test_RevertIf_DeactivateAlreadyInacitvePlan() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        manager.deactivatePlan(planId);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.PlanAlreadyInactive.selector);
        
        manager.deactivatePlan(planId);
    }

    function test_RevertIf_ActivateAlreadyActivePlan() public {
        uint256 planId = _createPlan();

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.PlanAlreadyActive.selector);
        
        manager.activatePlan(planId);
    }

    function test_GetSubscriptionOfReturnsSubscriptionId() public {
        uint256 planId = _createPlan();
        
        _fundAndApprove(subscriber, PRICE);

        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);

        uint256 storedSubscriptionId = manager.getSubscriptionOf(planId, subscriber);
        assertEq(storedSubscriptionId, subscriptionId);
    }

    function test_RevertIf_UserSubscribesTwiceToSamePlan() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE * 2);

        vm.prank(subscriber);
        manager.subscribe(planId);

        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.AlreadySubscribed.selector);
        manager.subscribe(planId);
    }
    
    function test_UserCanSubscribeAgainAfterCancelling() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE * 2);

        vm.prank(subscriber);
        uint256 subscriptionId1 = manager.subscribe(planId);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId1);

        vm.prank(subscriber);
        uint256 subscriptionId2 = manager.subscribe(planId);

        assertEq(subscriptionId1, 1);
        assertEq(subscriptionId2, 2);

        assertEq(manager.getSubscriptionOf(planId, subscriber), subscriptionId2);
    }
    
    function test_SameUserCanSubscribeToDifferentPlans() public {
        vm.startPrank(provider);

        uint256 planId1 = manager.createPlan(
            address(mockToken), 
            PRICE, 
            INTERVAL, 
            "metadataURI1"
        );

        uint256 planId2 = manager.createPlan(
            address(mockToken), 
            PRICE, 
            INTERVAL, 
            "metadataURI2"
        );

        vm.stopPrank();

        _fundAndApprove(subscriber, PRICE * 2);

        vm.prank(subscriber);
        uint256 subscriptionIdPlan1 = manager.subscribe(planId1);

        vm.prank(subscriber);
        uint256 subscriptionIdPlan2 = manager.subscribe(planId2);
        
        assertEq(subscriptionIdPlan1, 1);
        assertEq(subscriptionIdPlan2, 2);
        
        assertEq(manager.getSubscriptionOf(planId1, subscriber), subscriptionIdPlan1);
        assertEq(manager.getSubscriptionOf(planId2, subscriber), subscriptionIdPlan2);
    }
    
    function test_DifferentUsersCanSubscribeToSamePlan() public {
        uint256 planId = _createPlan();

        _fundAndApprove(subscriber, PRICE);
        _fundAndApprove(anotherSubscriber, PRICE);

        vm.prank(subscriber);
        uint256 subscriptionId1 = manager.subscribe(planId);

        vm.prank(anotherSubscriber);
        uint256 subscriptionId2 = manager.subscribe(planId);

        assertEq(subscriptionId1, 1);
        assertEq(subscriptionId2, 2);

        assertEq(manager.getSubscriptionOf(planId, subscriber), subscriptionId1);
        assertEq(manager.getSubscriptionOf(planId, anotherSubscriber), subscriptionId2);
    }
    
    function test_GetSubscriptionOfReturnsZeroAfterCancellation() public {
        uint256 planId = _createPlan();
        
        _fundAndApprove(subscriber, PRICE);
        
        vm.prank(subscriber);
        uint256 subscriptionId = manager.subscribe(planId);
        
        // Cancel subscription
        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);
        
        // Get subscription should return 0
        assertEq(manager.getSubscriptionOf(planId, subscriber), 0);
    }
    
    function test_RevertIf_GetSubscriptionOfInvalidPlan() public {
        _fundAndApprove(subscriber, PRICE);

        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.InvalidPlan.selector);
        manager.getSubscriptionOf(1, subscriber);
    }
    
    function test_RevertIf_GetSubscriptionOfZeroAddress() public {
        _createPlan();
        
        vm.expectRevert(SubscriptionManager.InvalidAddress.selector);
        manager.getSubscriptionOf(1, address(0));
    }

    ////////////////////////////////////////////////////////////////////////////////
    // markPastDue Tests
    ////////////////////////////////////////////////////////////////////////////////

    function test_MarkPastDueSetsStatus() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscriptionBefore = manager.getSubscription(subscriptionId);

        vm.warp(subscriptionBefore.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);

        SubscriptionManager.Subscription memory subscriptionAfter = manager.getSubscription(subscriptionId);

        assertEq(uint256(subscriptionAfter.status), uint256(SubscriptionManager.SubscriptionStatus.PAST_DUE));      
    }

    function test_MarkPastDueEmitsEvent() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.expectEmit(true, true, true, true);

        emit SubscriptionMarkedPastDue(
            subscriptionId,
            subscription.planId,
            subscriber,
            subscription.nextPaymentDue
        );

        vm.prank(provider);
        manager.markPastDue(subscriptionId);
    }
    
    function test_RevertIf_MarkPastDueInvalidSubscription() public {
        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.InvalidSubscription.selector);
        manager.markPastDue(1);
    }
    
    function test_RevertIf_NonProviderMarksPastDue() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(anotherProvider);
        vm.expectRevert(SubscriptionManager.Unauthorized.selector);

        manager.markPastDue(subscriptionId);
    }
    
    function test_RevertIf_MarkPastDueTooEarly() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.ChargeNotDue.selector);
        
        manager.markPastDue(subscriptionId);
    }
    
    function test_RevertIf_MarkPastDueCancelledSubscription() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(subscriber);
        manager.cancelSubscription(subscriptionId);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.SubscriptionNotActive.selector);

        manager.markPastDue(subscriptionId);
    }
    
    function test_RevertIf_MarkPastDueAlreadyPastDue() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.SubscriptionNotActive.selector);
        manager.markPastDue(subscriptionId);
    }

    function test_RevertIf_ChargePastDueSubscription() public {
        uint256 subscriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        manager.markPastDue(subscriptionId);

        vm.prank(provider);
        vm.expectRevert(SubscriptionManager.SubscriptionNotActive.selector);
        manager.charge(subscriptionId);
    }

    /////////////////////////////////////////////////////////////////////
    // Reactivate Past Due Subscription Tests
    /////////////////////////////////////////////////////////////////////
    function test_ReactivatePastDueSubscriptionSetsActive() public {
        uint256 subscriptionId = _createPastDueSubscription();
        
        vm.prank(subscriber);
        manager.reactivatePastDueSubscription(subscriptionId);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        assertEq(uint256(subscription.status), uint256(SubscriptionManager.SubscriptionStatus.ACTIVE));
    }

    function test_ReactivatePastDueSubscriptionTransfersPayment() public {
        uint256 subscriptionId = _createPastDueSubscription();

        uint256 providerBalanceBefore = mockToken.balanceOf(provider);
        uint256 subscriberBalanceBefore = mockToken.balanceOf(subscriber);
        
        vm.prank(subscriber);
        manager.reactivatePastDueSubscription(subscriptionId);

        assertEq(mockToken.balanceOf(provider), providerBalanceBefore + PRICE);
        assertEq(mockToken.balanceOf(subscriber), subscriberBalanceBefore - PRICE);


    }

    function test_ReactivatePastDueSubscriptionUpdatesNextPaymentDue() public {
        uint256 subscriptionId = _createPastDueSubscription();
        
        SubscriptionManager.Subscription memory subscriptionBefore = manager.getSubscription(subscriptionId);
        uint256 expectedNextPaymentDueBefore = subscriptionBefore.nextPaymentDue;
        
        vm.prank(subscriber);
        manager.reactivatePastDueSubscription(subscriptionId);
        
        SubscriptionManager.Subscription memory subscriptionAfter = manager.getSubscription(subscriptionId);
        uint256 nextPaymentDueAfter = subscriptionAfter.nextPaymentDue;
        
        assertEq(nextPaymentDueAfter, expectedNextPaymentDueBefore + INTERVAL);
    }

    function test_ReactivatePastDueSubscriptionEmitsEvent() public {
        uint256 subscriptionId = _createPastDueSubscription();

        SubscriptionManager.Subscription memory subscription =
            manager.getSubscription(subscriptionId);

        uint256 expectedNextPaymentDue = subscription.nextPaymentDue + INTERVAL;

        vm.expectEmit(true, true, true, true);

        emit SubscriptionReactivated(
            subscriptionId,
            subscription.planId,
            subscriber,
            PRICE,
            expectedNextPaymentDue
        );

        vm.prank(subscriber);
        manager.reactivatePastDueSubscription(subscriptionId);
    }

    function test_RevertIf_ReactivateInvalidSubscription() public {
        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.InvalidSubscription.selector);

        manager.reactivatePastDueSubscription(1);
    }

    function test_RevertIf_ReactivateSubscriptionNotPastDue() public {
        uint256 subcriptionId = _createSubscriptionWithBalanceAndAllowance(PRICE * 2);

        vm.prank(subscriber);
        vm.expectRevert(SubscriptionManager.SubscriptionNotPastDue.selector);

        manager.reactivatePastDueSubscription(subcriptionId);
    }

    function test_RevertIf_NonSubscriberReactivates() public {
        uint256 subscriptionId = _createPastDueSubscription();

        vm.prank(anotherSubscriber);
        vm.expectRevert(SubscriptionManager.Unauthorized.selector);

        manager.reactivatePastDueSubscription(subscriptionId);
    }

    function test_RevertIf_ReactivateWithoutAllowance() public {
        uint256 subscriptionId = _createPastDueSubscriptionWithoutRemainingAllowance();

        mockToken.mint(subscriber, PRICE);

        vm.prank(subscriber);
        vm.expectRevert();

        manager.reactivatePastDueSubscription(subscriptionId);
    }

    function test_RevertIf_ReactivateWithoutEnoughBalance() public {
        uint256 subscriptionId = _createPastDueSubscriptionWithoutRemainingAllowance();

        vm.prank(subscriber);
        mockToken.approve(address(manager), PRICE - 1);

        vm.expectRevert();
        vm.prank(subscriber);

        manager.reactivatePastDueSubscription(subscriptionId);
    }

    function test_CanChargeAfterPastDueReactivation() public {
        uint256 subscriptionId = _createPastDueSubscription();

        vm.prank(subscriber);
        manager.reactivatePastDueSubscription(subscriptionId);

        SubscriptionManager.Subscription memory subscription = manager.getSubscription(subscriptionId);

        _fundAndApprove(subscriber, PRICE);

        vm.warp(subscription.nextPaymentDue);

        vm.prank(provider);
        manager.charge(subscriptionId);

        SubscriptionManager.Subscription memory subscriptionAfterCharge = manager.getSubscription(subscriptionId);

        assertEq(uint256(subscriptionAfterCharge.status), uint256(SubscriptionManager.SubscriptionStatus.ACTIVE));

        assertEq(subscriptionAfterCharge.nextPaymentDue, subscription.nextPaymentDue + INTERVAL);
    }

}