// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SubscriptionManager
/// @notice Base contract for recurring ERC20 subscriptions.
contract SubscriptionManager {

    uint256 public nextPlanId;
    uint256 public nextSubscriptionId;

    mapping(uint256 => Plan) private plans;
    mapping(uint256 => Subscription) private subscriptions;
    //mapping(uint256 planId => mapping(address subscriber => Subscription subscription)) public subscriptions;


    enum SubscriptionStatus {
        NONE,
        ACTIVE,
        PAST_DUE,
        EXPIRED,
        PAUSED,
        CANCELLED
    }

    struct Plan {
        address provider;
        address token;
        uint256 pricePerInterval;
        uint256 interval;
        string metadataURI;
        bool active;
    }

    struct Subscription {
        uint256 planId;
        address subscriber;
        uint256 nextPaymentDue;
        SubscriptionStatus status;
    }

    error InvalidAddress();
    error InvalidAmount();
    error InvalidInterval();
    error InvalidPlan();
    error Unauthorized();
    error PlanInactive();
    error AlreadySubscribed();
    error SubscriptionNotActive();
    error ChargeNotDue();
    error InvalidSubscription();
    error PaymentFailed();

    event PlanCreated(
        uint256 indexed planId,
        address indexed provider,
        address indexed token,
        uint256 pricePerInterval,
        uint256 interval,
        string metadataURI
    );
    event PlanStatusUpdated(uint256 indexed planId, bool active);
    event Subscribed(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint256 nextPaymentDue);
    event SubscriptionCharged(uint256 indexed subscriptionId,uint256 indexed planId, address indexed subscriber, uint256 amount, uint256 nextChargeAt);
    event SubscriptionPastDue(uint256 indexed planId, address indexed subscriber);
    event SubscriptionCancelled(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber);
    event Charged(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint256 amount, uint256 nextPaymentDue);


    function createPlan(address token, uint256 pricePerInterval, uint256 interval, string calldata metadataURI) external returns (uint256 planId) {
        if (token == address(0)) revert InvalidAddress();
        if (pricePerInterval == 0) revert InvalidAmount();
        if (interval == 0) revert InvalidInterval();

        planId = ++nextPlanId;
        plans[planId] = Plan({
            provider: msg.sender,
            token: token,
            pricePerInterval: pricePerInterval,
            interval: interval,
            metadataURI: metadataURI,
            active: true
        });

        emit PlanCreated(planId, msg.sender, token, pricePerInterval, interval, metadataURI);
    }

    function subscribe(uint256 planId) external returns (uint256 subscriptionId) {
        if (planId == 0 || planId > nextPlanId) revert InvalidPlan();

        Plan memory plan = plans[planId];

        if(!plan.active) revert PlanInactive();

        bool success = IERC20(plan.token).transferFrom(msg.sender, plan.provider, plan.pricePerInterval);

        if (!success) revert PaymentFailed();

        subscriptionId = ++nextSubscriptionId;

        uint256 nextPaymentDue = block.timestamp + plan.interval;

        subscriptions[subscriptionId] = Subscription({
            planId: planId,
            subscriber: msg.sender,
            nextPaymentDue: nextPaymentDue,
            status: SubscriptionStatus.ACTIVE
        });
        

        emit Subscribed(subscriptionId, planId, msg.sender, nextPaymentDue);
    }

    function charge(uint256 subscriptionId) external {
        if (subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();

        Subscription storage subscription = subscriptions[subscriptionId];
        
        if(subscription.status != SubscriptionStatus.ACTIVE) revert SubscriptionNotActive();

        Plan memory plan = plans[subscription.planId];

        if (msg.sender != plan.provider) revert Unauthorized();

        if (block.timestamp < subscription.nextPaymentDue) revert ChargeNotDue();

        bool success = IERC20(plan.token).transferFrom(
            subscription.subscriber, 
            plan.provider, 
            plan.pricePerInterval
        );
        
        if (!success) revert PaymentFailed();

        subscription.nextPaymentDue = block.timestamp + plan.interval;
        
        emit SubscriptionCharged(subscriptionId, subscription.planId, subscription.subscriber, plan.pricePerInterval, subscription.nextPaymentDue);
    }

    function cancelSubscription(uint256 subscriptionId) external {
        if(subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();

        Subscription storage subscription = subscriptions[subscriptionId];

        if(subscription.status != SubscriptionStatus.ACTIVE) revert SubscriptionNotActive();

        if(msg.sender != subscription.subscriber) revert Unauthorized();

        subscription.status = SubscriptionStatus.CANCELLED;
        
        emit SubscriptionCancelled(subscriptionId, subscription.planId, subscription.subscriber);
    }

    function getPlan(uint256 planId) external view returns (Plan memory){
        if (planId == 0 || planId > nextPlanId) revert InvalidPlan();

        return plans[planId];
    }

    function getSubscription(uint256 subscriptionId) external view returns(Subscription memory) {
        if (subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();

        return subscriptions[subscriptionId];
    }

    function activatePlan(uint256 planId) external {
        // TODO: Implement plan activation logic
    }

    function deactivatePlan(uint256 planId) external {
        //TODO: Implement plan deactivation logic
    }
/*
    function setPlanStatus(uint256 planId, bool active) external {
        Plan storage plan = plans[planId];
        if (plan.provider == address(0)) revert InvalidPlan();
        if (plan.provider != msg.sender) revert Unauthorized();

        plan.active = active;
        emit PlanStatusUpdated(planId, active);
    }

    function subscribe(uint256 planId) external {
        Plan memory plan = plans[planId];
        if (plan.provider == address(0)) revert InvalidPlan();
        if (!plan.active) revert PlanInactive();

        Subscription storage currentSubscription = subscriptions[planId][msg.sender];
        if (currentSubscription.status == SubscriptionStatus.ACTIVE) revert AlreadySubscribed();

        uint256 nextChargeAt = block.timestamp + plan.interval;
        subscriptions[planId][msg.sender] = Subscription({
            startedAt: block.timestamp,
            nextChargeAt: nextChargeAt,
            status: SubscriptionStatus.ACTIVE
        });

        emit Subscribed(planId, msg.sender, nextChargeAt);
    }

    function chargeSubscription(uint256 planId, address subscriber) external returns (bool success) {
        Plan memory plan = plans[planId];
        if (plan.provider == address(0)) revert InvalidPlan();
        if (plan.provider != msg.sender) revert Unauthorized();
        if (!plan.active) revert PlanInactive();

        Subscription storage userSubscription = subscriptions[planId][subscriber];
        if (userSubscription.status != SubscriptionStatus.ACTIVE) revert SubscriptionNotActive();
        if (block.timestamp < userSubscription.nextChargeAt) revert ChargeNotDue();

        IERC20 token = IERC20(plan.token);
        uint256 amount = plan.pricePerInterval;

        if (token.allowance(subscriber, address(this)) < amount || token.balanceOf(subscriber) < amount) {
            userSubscription.status = SubscriptionStatus.PAST_DUE;
            emit SubscriptionPastDue(planId, subscriber);
            return false;
        }

        success = token.transferFrom(subscriber, plan.provider, amount);
        if (!success) {
            userSubscription.status = SubscriptionStatus.PAST_DUE;
            emit SubscriptionPastDue(planId, subscriber);
            return false;
        }

        userSubscription.nextChargeAt += plan.interval;
        emit SubscriptionCharged(planId, subscriber, amount, userSubscription.nextChargeAt);
    }

    function cancelSubscription(uint256 planId) external {
        Subscription storage userSubscription = subscriptions[planId][msg.sender];
        if (userSubscription.status != SubscriptionStatus.ACTIVE && userSubscription.status != SubscriptionStatus.PAST_DUE) {
            revert SubscriptionNotActive();
        }

        userSubscription.status = SubscriptionStatus.CANCELED;
        emit SubscriptionCanceled(planId, msg.sender);
    }

    function getSubscriptionStatus(uint256 planId, address subscriber) external view returns (SubscriptionStatus) {
        return subscriptions[planId][subscriber].status;
    }
    */
}
