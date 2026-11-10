# ADR-006: Messaging and Event Transport

- **Status:** Proposed for review
- **Context/problem:** Need reliable event-driven side effects without premature broker operations.
- **Options:** PostgreSQL outbox + worker; RabbitMQ/managed queue; Kafka.
- **Evaluation:** Outbox is simplest and transactionally coupled, suitable for MVP volume. Queue helps work delivery/retry. Kafka supports replayable high-throughput streams but requires expertise/ops and is excessive without volume evidence.
- **Decision:** Begin with PostgreSQL outbox and worker; add managed task queue as durable fanout demands. Keep Kafka as later evaluated option.
- **Consequences:** At-least-once processing, inbox/idempotency, DLQ and replay tooling required.
- **Risks:** Outbox polling can pressure DB; no global order guarantee.
- **Revisit when:** Measured throughput, replay, consumer count or retention needs exceed queue/outbox design.
