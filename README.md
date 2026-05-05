# SubscriptionManager

Protocolo base en Solidity para manejar suscripciones recurrentes con ERC20.

## Estado actual

El proyecto quedó **inicializado con una base funcional**, no con la implementación completa final.

Hoy incluye:

- contrato base `SubscriptionManager`
- creación y activación/desactivación de planes
- suscripción de usuarios a un plan
- cobro recurrente usando `transferFrom` sobre un ERC20
- transición a estado `PAST_DUE` si no hay balance o allowance suficiente
- cancelación de suscripción
- script mínimo de deploy
- tests base de creación de plan y suscripción

## Idea del protocolo

Un proveedor publica un plan:

- token ERC20 a cobrar
- precio por período
- intervalo de cobro

Luego un usuario se suscribe y autoriza al contrato. Cuando llega `nextChargeAt`, el proveedor puede ejecutar el cobro.

## Arquitectura base

### Entidades principales

#### Plan

Representa la oferta publicada por un proveedor.

Campos principales:

- `provider`
- `token`
- `pricePerInterval`
- `interval`
- `active`

#### Subscription

Representa la relación entre un usuario y un plan.

Campos principales:

- `startedAt`
- `nextChargeAt`
- `status`

#### Estados

- `NONE`
- `ACTIVE`
- `PAST_DUE`
- `CANCELED`

## Contrato actual

Archivo: `src/SubscriptionManager.sol`

### Funciones disponibles

- `createPlan(address token, uint256 pricePerInterval, uint256 interval)`
- `setPlanStatus(uint256 planId, bool active)`
- `subscribe(uint256 planId)`
- `chargeSubscription(uint256 planId, address subscriber)`
  - revierte con `ChargeNotDue()` si todavía no llegó el momento del cobro
- `cancelSubscription(uint256 planId)`
- `getSubscriptionStatus(uint256 planId, address subscriber)`

## Decisiones tomadas en esta base

### 1. El cobro lo ejecuta el provider

Esto sigue el modelo planteado en `Task.md`: el usuario autoriza, pero quien dispara el cobro es el proveedor.

### 2. Si el cobro falla, la suscripción pasa a `PAST_DUE`

En vez de asumir que todo revierte y nada más, la base ya modela el estado de deuda/impago.

### 3. No agregué fee de protocolo ni factory todavía

Eso es una decisión correcta PARA ESTA ETAPA. Primero hay que cerrar bien el flujo núcleo antes de meter complejidad adicional.

## Qué falta

Esto todavía NO cubre:

- reactivación de suscripciones vencidas
- fee del protocolo
- factory de planes o providers
- sistema de múltiples planes premium/basic/etc.
- pausas más finas
- control de reintentos de cobro
- tests de fuzz
- tests de invariantes
- mocks ERC20 para escenarios completos de cobro
- hardening de seguridad y gas optimization

## Estructura del proyecto

```txt
src/
  SubscriptionManager.sol
script/
  SubscriptionManager.s.sol
test/
  SubscriptionManager.t.sol
```

## Desarrollo

### Instalar dependencias

Este repo ya viene preparado para usar `forge-std` como submodule.

### Tests

```bash
forge test
```

### Formato

```bash
forge fmt
```

## Siguiente paso recomendado

El siguiente paso sano NO es agregar features al azar.

Primero hay que hacer esto:

1. agregar un `MockERC20`
2. testear el flujo completo de `chargeSubscription`
3. cubrir `PAST_DUE`
4. recién después evaluar fees, factory e invariants
