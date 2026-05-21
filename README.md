# SubscriptionManager

A Foundry-based Solidity project for managing recurring ERC20 subscriptions.

## Overview

`SubscriptionManager` is a base on-chain subscription protocol where:

- a provider creates a plan,
- a user subscribes with an ERC20 token,
- the first payment is charged immediately on subscription,
- future payments can be charged periodically by the provider,
- each payment can split value between the provider and a protocol treasury.

This repository is intentionally positioned as a **base implementation**. It is useful for learning, iteration, and hardening, but it is **not production-ready** and has **not been audited**.

## Current implementation status

The current contract already supports the core lifecycle:

- plan creation with token, price, interval, and metadata URI
- constructor-based treasury + protocol fee configuration
- provider-controlled plan activation and deactivation
- user subscription with an upfront ERC20 payment
- recurring provider-triggered charges once a payment is due
- manual transition to `PAST_DUE` when a due subscription needs to be flagged
- subscriber-driven reactivation from `PAST_DUE`
- user cancellation
- automatic payment split between provider and treasury on subscribe / charge / reactivation
- subscription lookup helpers
- unit tests for the main happy paths, fee flow, and key revert scenarios

## How it works

### Protocol fee model

The contract is deployed with:

- `treasury`: address that receives the protocol fee
- `protocolFeeBps`: fee expressed in basis points (`10_000 = 100%`)

Every successful payment is split into:

- provider amount = `amount - fee`
- protocol fee = `amount * protocolFeeBps / 10_000`

If `protocolFeeBps` is `0`, the full payment goes to the provider.

### Plan lifecycle

A provider creates a plan with:

- `token`: ERC20 token used for billing
- `pricePerInterval`: amount charged every billing cycle
- `interval`: billing period in seconds
- `metadataURI`: off-chain metadata pointer for plan details

Plans are active by default and can later be deactivated or reactivated by their provider.
Deactivation blocks **new** subscriptions, but existing active subscriptions can still be charged.

### Subscription lifecycle

When a user subscribes:

1. the contract pulls the **first payment immediately** using `transferFrom`,
2. a subscription record is created,
3. `nextPaymentDue` is set to `block.timestamp + interval`.

When the due date is reached, the provider can call `charge(subscriptionId)` to collect the next payment.

If the subscription should be flagged as overdue after the due date, the provider can call `markPastDue(subscriptionId)`.

A `PAST_DUE` subscriber can restore the subscription by calling `reactivatePastDueSubscription(subscriptionId)`, which charges one interval again and resets `nextPaymentDue`.

A subscriber can cancel their own active subscription at any time.

## Contract API

Main contract: `src/SubscriptionManager.sol`

### Constructor

- `constructor(address treasury, uint256 protocolFeeBps)`

### Write functions

- `createPlan(address token, uint256 pricePerInterval, uint256 interval, string calldata metadataURI)`
- `deactivatePlan(uint256 planId)`
- `activatePlan(uint256 planId)`
- `subscribe(uint256 planId)`
- `charge(uint256 subscriptionId)`
- `markPastDue(uint256 subscriptionId)`
- `reactivatePastDueSubscription(uint256 subscriptionId)`
- `cancelSubscription(uint256 subscriptionId)`

### Read functions

- `getPlan(uint256 planId)`
- `getSubscription(uint256 subscriptionId)`
- `getSubscriptionOf(uint256 planId, address subscriber)`
- `treasury()`
- `protocolFeeBps()`
- `BPS()`
- `nextPlanId()`
- `nextSubscriptionId()`

## State model

### Global configuration

The contract stores:

- treasury address
- protocol fee in basis points
- incremental counters for plans and subscriptions

### Plan

A plan stores:

- provider address
- ERC20 token address
- price per billing interval
- billing interval
- metadata URI
- active flag

### Subscription

A subscription stores:

- plan ID
- subscriber address
- next payment due timestamp
- subscription status

### Subscription statuses

The enum currently includes:

- `NONE`
- `ACTIVE`
- `PAST_DUE`
- `EXPIRED`
- `PAUSED`
- `CANCELLED`

At the moment, the implemented flows actively use `ACTIVE`, `PAST_DUE`, and `CANCELLED`. The additional statuses exist in the contract but are not yet part of a full lifecycle implementation.

## Repository structure

```txt
src/
  SubscriptionManager.sol
script/
  SubscriptionManager.s.sol
test/
  SubscriptionManager.t.sol
  mocks/
    MockERC20.sol
```

## Development

### Dependencies

This project uses:

- Foundry
- OpenZeppelin Contracts (via git submodule/remapping)
- forge-std

If needed, initialize submodules before working with the repo:

```bash
git submodule update --init --recursive
```

### Run tests

```bash
forge test
```

### Format

```bash
forge fmt
```

### Deployment script note

`script/SubscriptionManager.s.sol` now deploys the contract with constructor parameters.

Before running the script, you **must** provide the treasury via environment variable:

```bash
TREASURY=0xYourTreasuryAddress forge script script/SubscriptionManager.s.sol:SubscriptionManagerScript
```

Optionally, you can override the fee too:

```bash
TREASURY=0xYourTreasuryAddress PROTOCOL_FEE_BPS=100 forge script script/SubscriptionManager.s.sol:SubscriptionManagerScript
```

If `TREASURY` is missing or invalid, deployment reverts before the contract can be created.

## Current limitations

This base version does **not** yet provide a complete production-grade subscription system. For example:

- no factory layer for plan deployment or provider isolation
- no automatic retry or dunning strategy
- no admin/governance flow to rotate treasury or update protocol fees after deployment
- no automatic recovery flow beyond manual subscriber reactivation
- no fully implemented `PAUSED` / `EXPIRED` lifecycle
- no automation layer for scheduled execution
- no fuzz or invariant test suite yet
- no audit or security review yet

## Future direction

The next meaningful iterations should prioritize **making the existing flow safer and more robust before adding complexity**.

That means focusing on hardening areas such as:

- payment-failure handling and overdue strategy
- lifecycle edge cases and state-transition guarantees
- broader testing depth, especially fuzz and invariant coverage
- security review of permissions, assumptions, and external token interactions

Only after that should larger product features such as factories, richer plan systems, or fee-governance layers be expanded.

## Notes

This repository is a good base for:

- practicing Solidity architecture and state-machine design
- learning recurring-payment flows with ERC20 tokens
- understanding protocol-fee splitting on top of recurring billing
- discussing tradeoffs around pull-based subscription billing in Web3
- evolving a prototype into a safer protocol through iterative hardening
