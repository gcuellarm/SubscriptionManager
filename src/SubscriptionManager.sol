// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title SubscriptionManager
/// @notice Base contract for recurring ERC20 subscriptions.
contract SubscriptionManager {
    enum SubscriptionStatus {
        NONE,
        ACTIVE,
        PAST_DUE,
        CANCELED
    }

    struct Plan {
        address provider;
        address token;
        uint256 pricePerInterval;
        uint256 interval;
        bool active;
    }

    struct Subscription {
        uint256 startedAt;
        uint256 nextChargeAt;
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

    event PlanCreated(
        uint256 indexed planId,
        address indexed provider,
        address indexed token,
        uint256 pricePerInterval,
        uint256 interval
    );
    event PlanStatusUpdated(uint256 indexed planId, bool active);
    event Subscribed(uint256 indexed planId, address indexed subscriber, uint256 nextChargeAt);
    event SubscriptionCharged(uint256 indexed planId, address indexed subscriber, uint256 amount, uint256 nextChargeAt);
    event SubscriptionPastDue(uint256 indexed planId, address indexed subscriber);
    event SubscriptionCanceled(uint256 indexed planId, address indexed subscriber);

    uint256 public nextPlanId;

    mapping(uint256 planId => Plan plan) public plans;
    mapping(uint256 planId => mapping(address subscriber => Subscription subscription)) public subscriptions;

    function createPlan(address token, uint256 pricePerInterval, uint256 interval) external returns (uint256 planId) {
        if (token == address(0)) revert InvalidAddress();
        if (pricePerInterval == 0) revert InvalidAmount();
        if (interval == 0) revert InvalidInterval();

        planId = nextPlanId++;
        plans[planId] = Plan({
            provider: msg.sender,
            token: token,
            pricePerInterval: pricePerInterval,
            interval: interval,
            active: true
        });

        emit PlanCreated(planId, msg.sender, token, pricePerInterval, interval);
    }

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
}
