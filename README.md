# SubscriptionManager

Base Solidity protocol for managing recurring subscriptions with ERC20 tokens.

## Current status

The project has been **initialized with a functional base**, not with the complete final implementation.

It currently includes:

- base `SubscriptionManager` contract
- plan creation and plan activation/deactivation
- user subscription to a plan
- recurring charges using `transferFrom` on an ERC20 token
- transition to `PAST_DUE` status when there is not enough balance or allowance
- subscription cancellation
- minimal deploy script
- base tests for plan creation and subscription

## Protocol idea

A provider publishes a plan:

- ERC20 token to charge
- price per period
- billing interval

Then a user subscribes and authorizes the contract. When `nextChargeAt` is reached, the provider can execute the charge.

## Base architecture

### Main entities

#### Plan

Represents the offer published by a provider.

Main fields:

- `provider`
- `token`
- `pricePerInterval`
- `interval`
- `active`

#### Subscription

Represents the relationship between a user and a plan.

Main fields:

- `startedAt`
- `nextChargeAt`
- `status`

#### Statuses

- `NONE`
- `ACTIVE`
- `PAST_DUE`
- `CANCELED`

## Current contract

File: `src/SubscriptionManager.sol`

### Available functions

- `createPlan(address token, uint256 pricePerInterval, uint256 interval)`
- `setPlanStatus(uint256 planId, bool active)`
- `subscribe(uint256 planId)`
- `chargeSubscription(uint256 planId, address subscriber)`
  - reverts with `ChargeNotDue()` if the charge is not due yet
- `cancelSubscription(uint256 planId)`
- `getSubscriptionStatus(uint256 planId, address subscriber)`

## Decisions made in this base

### 1. Charges are executed by the provider

This follows the model described in `Task.md`: the user authorizes the contract, but the provider triggers the charge.

### 2. If the charge fails, the subscription moves to `PAST_DUE`

Instead of assuming everything simply reverts and nothing else happens, this base already models the debt/non-payment state.

### 3. I have not added a protocol fee or factory yet

That is the right decision FOR THIS STAGE. First, the core flow needs to be properly closed before adding extra complexity.

## What is missing

This still does NOT cover:

- reactivation of expired subscriptions
- protocol fee
- plan or provider factory
- multiple plan system, such as premium/basic/etc.
- more granular pause controls
- charge retry control
- fuzz tests
- invariant tests
- ERC20 mocks for complete charge scenarios
- security hardening and gas optimization

## Project structure

```txt
src/
  SubscriptionManager.sol
script/
  SubscriptionManager.s.sol
test/
  SubscriptionManager.t.sol
```

## Development

### Install dependencies

This repo is already prepared to use `forge-std` as a submodule.

### Tests

```bash
forge test
```

### Formatting

```bash
forge fmt
```

## Recommended next step

The healthy next step is NOT to add random features.

First, this needs to be done:

1. add a `MockERC20`
2. test the full `chargeSubscription` flow
3. cover `PAST_DUE`
4. only then evaluate fees, factory, and invariants
