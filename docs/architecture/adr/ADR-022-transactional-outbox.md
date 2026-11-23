# ADR-022 — Transactional outbox and consumer inbox

- Status: Proposed — prepared under the owner's "architecture first" rule (2026-11-23). The infrastructure is additive and **off by default**; no product publishes events yet, and no financial flow is touched.
- Date: 2026-11-23
- Scope: how a business fact leaves a transaction reliably (in-process today, to another service or broker later)
- Builds on: ADR-006 (messaging platform), [14-event-driven-architecture](../14-event-driven-architecture.md), ADR-021

## Context
Today there are no events. Products call each other's services or read each other's tables (the coupling tracked in the architecture baseline). Once a product is
extracted, those calls become network calls and a side effect (notification, search index, analytics, a read model in another service) must follow a committed
state change. Doing that with a direct call after commit loses events on a crash; calling before commit publishes facts that roll back. Retrofitting the
"write the event in the same transaction" step into every flow later means touching each one under production load; the table and the writer are cheap now.

## Alternatives
1. **Publish to a broker after commit.** Simple, but a crash between commit and publish loses the event, and the reverse order publishes rolled-back facts. Needs distributed
   transactions to be correct. Rejected.
2. **Spring `ApplicationEventPublisher` / `@TransactionalEventListener`.** In-memory, lost on crash or restart, invisible to other instances. Fine for same-request
   side effects, not for a durable contract. Rejected as the contract (still usable inside a module).
3. **CDC on business tables (Debezium).** No application code, but couples consumers to table shapes (the thing we are removing) and needs Kafka Connect now. Deferred; the outbox
   table can later be the CDC source without changing producers.
4. **Transactional outbox in PostgreSQL with an in-process relay (chosen).** Same database and transaction as the business change, no new infrastructure, works with several
   instances, and the relay can later forward to a queue or broker unchanged for producers.

## Decision
- Tables `platform.outbox_events` and `platform.inbox_events` (Flyway V68, expand-only). Envelope as in doc 14: `event_id`, `event_type` (`kunde.<aggregate>.<fact>`),
  `schema_version`, `producer`, aggregate type/id/version, `correlation_id`, `causation_id`, `occurred_at`, `payload` (jsonb), plus `city_id` as a placement hint (no foreign key).
- `OutboxWriter.append` runs only inside a business transaction (`MANDATORY`): the event and the state change commit or roll back together.
- `OutboxRelay` claims one event with `FOR UPDATE SKIP LOCKED` (any number of instances), keeps **per-aggregate order** (a later event is not claimed while an earlier one is PENDING or DEAD),
  records each consumer's success in the inbox inside a savepoint (retry never repeats a finished consumer), backs off exponentially with jitter, and dead-letters after `app.outbox.max-attempts`.
  A dead letter blocks its aggregate on purpose: for orders and payments a silently skipped fact is worse than a stopped stream. Only the exception class name is stored, never a message or payload.
- **Versioning.** A consumer declares `maxSchemaVersion`; a higher version is a permanent failure (dead letter), never a guess. Producers add fields within a version and publish a new version for incompatible changes; old versions
  are published in parallel until consumers move.
- **Off by default**: the scheduled relay runs only with `app.outbox.relay-enabled=true`. Metrics `kunde.outbox.delivered|retried|dead`.
- Placement class `LOCAL` in the placement registry: every database (global or shard) has its own outbox/inbox; a row stays with the transaction that wrote it and is never moved.

## First events (not implemented here)
`OrderCreated/Confirmed/Cancelled`, `PaymentCompleted/Failed`, `RefundCompleted`, `TripStarted/Completed`, `DeliveryCompleted`. Each is wired in its own PR, after its transaction boundary and
consumer are identified and, for payments and refunds, after the correctness argument for the financial flow is reviewed. The outbox write never changes a financial outcome: it is an extra insert in the same transaction.

## Consequences
- Delivery is at-least-once; consumers that call external systems still need their own idempotency by `event_id`.
- Table growth: delivered rows need a retention job (delete after N days) before the first producer goes live; not built yet because nothing writes.
- Ordering is per aggregate only. Cross-aggregate order needs the consumer to tolerate reordering or a saga.
- Dead-letter replay/resolve tooling for operators is **not built**; until it exists, enable the relay only for non-financial events.
- At extraction the in-process consumers become remote subscribers behind the same `EventConsumer` contract; the relay forwards to a queue instead of calling a bean.

## Not decided
Broker choice (ADR-006 stays Proposed), retention period, who may replay dead letters, and the first producer.
