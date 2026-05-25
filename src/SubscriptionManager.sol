// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SubscriptionManager
/// @notice Base contract for recurring ERC20 subscriptions.
contract SubscriptionManager {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;

    uint256 public nextPlanId;
    uint256 public nextSubscriptionId;
    address public treasury;
    uint256 public protocolFeeBps;

    mapping(uint256 => Plan) private plans;
    mapping(uint256 => Subscription) private subscriptions;
    mapping(uint256 planId => mapping(address subscriber => uint256 subscriptionId)) private subscriptionOf;


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
    error SubscriptionNotPastDue();
    error ChargeNotDue();
    error InvalidSubscription();
    error PlanAlreadyActive();
    error PlanAlreadyInactive();
    error InvalidFee();

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
    event PlanDeactivated(uint256 indexed planId, address indexed provider);
    event PlanActivated(uint256 indexed planId, address indexed provider);
    event SubscriptionMarkedPastDue(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint256 dueTimestamp);
    event SubscriptionReactivated(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint256 amount, uint256 nextPaymentDue);
    event ProtocolFeeCollected(address indexed token, address indexed payer, address indexed treasury, uint256 amount);

    constructor(address _treasury, uint256 _protocolFeeBps) {
        if (_treasury == address(0)) revert InvalidAddress();
        if (_protocolFeeBps > 10000) revert InvalidFee();

        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
    }


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

    function deactivatePlan(uint256 planId) external {
        if(planId == 0 || planId > nextPlanId) revert InvalidPlan();
        
        Plan storage plan = plans[planId];

        if(msg.sender != plan.provider) revert Unauthorized();
        if(!plan.active) revert PlanAlreadyInactive();
        
        plan.active = false;
        
        emit PlanDeactivated(planId, msg.sender);
        emit PlanStatusUpdated(planId, false);
    }

    function activatePlan(uint256 planId) external {
        if(planId == 0 || planId > nextPlanId) revert InvalidPlan();
        
        Plan storage plan = plans[planId];

        if(msg.sender != plan.provider) revert Unauthorized();
        if(plan.active) revert PlanAlreadyActive();
        
        plan.active = true;
        
        emit PlanActivated(planId, msg.sender);
        emit PlanStatusUpdated(planId, true);
    }

    function subscribe(uint256 planId) external returns (uint256 subscriptionId) {
        if (planId == 0 || planId > nextPlanId) revert InvalidPlan();

        Plan memory plan = plans[planId];

        if(!plan.active) revert PlanInactive();

        if(subscriptionOf[planId][msg.sender] != 0) revert AlreadySubscribed();

        _processPayment(plan.token, msg.sender, plan.provider, plan.pricePerInterval);

        subscriptionId = ++nextSubscriptionId;

        uint256 nextPaymentDue = block.timestamp + plan.interval;

        subscriptions[subscriptionId] = Subscription({
            planId: planId,
            subscriber: msg.sender,
            nextPaymentDue: nextPaymentDue,
            status: SubscriptionStatus.ACTIVE
        });
        
        subscriptionOf[planId][msg.sender] = subscriptionId;

        emit Subscribed(subscriptionId, planId, msg.sender, nextPaymentDue);
    }

    function charge(uint256 subscriptionId) external {
        if (subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();

        Subscription storage subscription = subscriptions[subscriptionId];
        
        if(subscription.status != SubscriptionStatus.ACTIVE) revert SubscriptionNotActive();

        Plan memory plan = plans[subscription.planId];

        if (msg.sender != plan.provider) revert Unauthorized();

        if (block.timestamp < subscription.nextPaymentDue) revert ChargeNotDue();

        _processPayment(plan.token, subscription.subscriber, plan.provider, plan.pricePerInterval);

        subscription.nextPaymentDue = block.timestamp + plan.interval;
        
        emit SubscriptionCharged(subscriptionId, subscription.planId, subscription.subscriber, plan.pricePerInterval, subscription.nextPaymentDue);
    }

    function markPastDue(uint256 subscriptionId) external {
        if(subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();

        Subscription storage subscription = subscriptions[subscriptionId];

        if(subscription.status != SubscriptionStatus.ACTIVE) revert SubscriptionNotActive();

        Plan memory plan = plans[subscription.planId];

        if(msg.sender != plan.provider) revert Unauthorized();
        if (block.timestamp < subscription.nextPaymentDue) revert ChargeNotDue();

        subscription.status = SubscriptionStatus.PAST_DUE;
        
        emit SubscriptionMarkedPastDue(subscriptionId, subscription.planId, subscription.subscriber, subscription.nextPaymentDue);
    }

    function reactivatePastDueSubscription(uint256 subscriptionId) external {
        if (subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();
        
        Subscription storage subscription = subscriptions[subscriptionId];

        if (subscription.status != SubscriptionStatus.PAST_DUE) revert SubscriptionNotPastDue();
        
        if (msg.sender != subscription.subscriber) revert Unauthorized();

        Plan memory plan = plans[subscription.planId];

        _processPayment(plan.token, msg.sender, plan.provider, plan.pricePerInterval);

        subscription.status = SubscriptionStatus.ACTIVE;
        subscription.nextPaymentDue = block.timestamp + plan.interval;
        
        emit SubscriptionReactivated(subscriptionId, subscription.planId, subscription.subscriber, plan.pricePerInterval, subscription.nextPaymentDue);
    }

    function cancelSubscription(uint256 subscriptionId) external {
        if(subscriptionId == 0 || subscriptionId > nextSubscriptionId) revert InvalidSubscription();

        Subscription storage subscription = subscriptions[subscriptionId];

        if(subscription.status != SubscriptionStatus.ACTIVE) revert SubscriptionNotActive();

        if(msg.sender != subscription.subscriber) revert Unauthorized();

        subscription.status = SubscriptionStatus.CANCELLED;

        subscriptionOf[subscription.planId][subscription.subscriber] = 0;
        
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

    function getSubscriptionOf(uint256 planId, address subscriber) external view returns(uint256) {
        if(planId == 0 || planId > nextPlanId) revert InvalidPlan();
        if(subscriber == address(0)) revert InvalidAddress();
        
        return subscriptionOf[planId][subscriber];
    }

    // Internal Functions

    function _splitPayment(uint256 amount) internal view returns (uint256 providerAmount, uint256 feeAmount) {
        feeAmount = (amount * protocolFeeBps) / BPS;
        providerAmount = amount - feeAmount;
    }

    function _processPayment(address token, address payer, address provider, uint256 amount) internal returns (uint256 providerAmount, uint256 feeAmount) {
        (providerAmount, feeAmount) = _splitPayment(amount);

        IERC20(token).safeTransferFrom(payer, provider, providerAmount);

        if(feeAmount > 0) {
            IERC20(token).safeTransferFrom(payer, treasury, feeAmount);
        }

        emit ProtocolFeeCollected(token, payer, treasury, feeAmount);
    }
}
