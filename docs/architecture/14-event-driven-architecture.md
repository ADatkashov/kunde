# 14 — Event-Driven Architecture

Use synchronous APIs when caller needs a validated answer (login, quote, slot hold, command acceptance). Use async events for side effects, retries, fanout and projections (notifications, search indexing, analytics, reconciliation, fulfillment updates). Events are not a substitute for a query API or canonical database.

## Event contract

Envelope: `eventId`, `eventType` (past-tense domain fact, e.g. `kunde.order.created`), `schemaVersion`, `occurredAt`, `producer`, `aggregateType`, `aggregateId`, `aggregateVersion`, `correlationId`, `causationId`, `tenantId` if applicable, `data`. Payload excludes secrets and minimizes PII; consumers retrieve authorized details through API if needed. Schema registry may be added with Kafka, not required before.

## Candidate events

`user.registered`, `partner.registered`, `order.created`, `order.accepted`, `order.cancelled`, `booking.created`, `booking.confirmed`, `booking.cancelled`, `payment.initiated`, `payment.confirmed`, `payment.failed`, `refund.requested`, `refund.completed`, `provider.assigned`, `delivery.completed`, `review.created`. Publish only after the domain transaction commits through transactional outbox.

## Delivery and ordering

At-least-once delivery is assumed. Consumer inbox/dedup table unique on `(consumer,event_id)` or equivalent; business mutations also use idempotency keys. Order events keyed by aggregate ID preserve per-aggregate ordering when broker supports it; consumers reject stale aggregate versions and can fetch current state. No global ordering guarantee.

Outbox relay uses bounded polling or CDC later. Retry transient failures with exponential backoff+jitter and cap; nonretryable/poison events go to dead-letter queue with alert and replay tooling. Replay is audited and safe because effects are idempotent. Do not drop financial event on exhausted retry; quarantine and reconcile.

## Initial technology progression

Start with PostgreSQL outbox and a worker; introduce managed queue for durable decoupling/visibility if task delivery need justifies it. Kafka is a later option for high-volume, replayable multi-consumer streams and analytics. RabbitMQ/managed task queue suits work dispatch; neither changes source of truth. Event schema evolution is additive; consumers accept unknown optional fields and support N/N-1 producer compatibility.
