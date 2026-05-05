# On-Chain Subscription Payments Protocol
Un protocolo en Solidity para crear suscripciones recurrentes on-chain, estilo “Netflix/Spotify”, pero aplicado a Web3.
## Idea principal
Un usuario puede autorizar una suscripción pagando con un ERC20, y un proveedor puede ir cobrando periódicamente mientras la suscripción esté activa.
## Ejemplo
- Usuario se suscribe a un servicio.
- Paga 10 USDC cada 30 días.
- El proveedor puede ejecutar chargeSubscription(...) cuando toca cobrar.
- El usuario puede cancelar cuando quiera.
- Si no hay balance o allowance suficiente, el cobro falla y la suscripción queda marcada como impagada o vencida.

Este proyecto mezcla cosas que ya has tocado, pero con un enfoque nuevo:
- ERC20 payments.
- Time-based logic con block.timestamp.
- Access control.
- Custom errors.
- Events.
- State machines.
- Foundry testing serio.
- Fuzz testing.
- Invariant testing.
- Posible factory.
- Posible fee del protocolo.
- Posible sistema de planes.
- Muy explicable en GitHub y entrevistas.
