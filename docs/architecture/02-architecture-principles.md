# 02 — Architecture Principles

| Principle | Enforceable application |
|---|---|
| Domain-first boundaries | Each module owns schema/tables and business invariants. Cross-module reads use public queries, projections or events; no direct table joins across owners. |
| Modular before distributed | Compile-time module boundaries and dependency checks; one deployable core until an extraction trigger is met. |
| API-first | OpenAPI-described versioned REST; explicit commands, stable error envelopes, idempotency and compatibility policy. |
| Secure/privacy by default | Deny-by-default ABAC/RBAC, minimum data, scoped tenant access, encryption, audit, in-country deployment for Kazakhstan personal data pending legal validation. |
| Financial correctness | Immutable journal and provider reconciliation; money in integer minor units plus currency; no status inferred from HTTP response alone. |
| Resilience and recoverability | Timeouts, bounded retries, idempotent consumers, outbox, dead-letter/reconciliation queues and user-visible pending state. |
| Provider abstraction | Adapters isolate payment, SMS, maps, AI, search and notification vendors; capability contracts state what is supported. |
| Observable operations | Correlation IDs cross client/API/provider/event; metrics cover user outcomes and orphan/unknown financial transactions. |
| Portable regional design | Currency, locale, time zone, tax, service-area and retention policies are explicit configuration; no country-specific assumptions in shared domain rules. |
| Scale from evidence | Load-test measured hot paths; scale read/search/worker components independently only when justified. |
| Backward compatibility | Additive API/schema/event changes by default; expand-migrate-contract for data changes; explicit deprecation window. |
| AI is a caller, not authority | All tools call domain APIs; permission, confirmation, price, availability and state machine are rechecked at execution time. |

## Prohibited shortcuts

- Shared mutable database access between modules/services.
- “Exactly once” messaging claims; achieve exactly-once business effect through idempotency and deduplication.
- Long-lived payment or session secrets in mobile storage/logs.
- Direct LLM-to-database or LLM-to-payment-provider connections.
- Synchronous dependency chains across optional providers on the critical checkout path without timeout/fallback design.
- Global multi-region writes for the same customer/financial aggregate in initial phases.
