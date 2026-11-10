# 11 — Database Architecture

## Storage map

| Store | System role | Initial posture |
|---|---|---|
| PostgreSQL | Canonical transactional data, permissions, orders, booking, payment references/journal, outbox; PostGIS extension for geo predicates | One managed cluster in verified Kazakhstan region; schema/role isolation by module; PITR/backup enabled |
| Redis-compatible cache | Short-lived nonauthoritative cache, rate-limit counters, ephemeral locks only if DB-safe alternative inadequate | Defer until measured; never source of truth for money/booking slot |
| Search index | Denormalized catalog/search projection | PostgreSQL search first; OpenSearch later with replayable projection |
| Object storage | Private evidence, product images, generated receipts | Regional encrypted bucket, signed short-lived URLs, malware/content checks where uploads accepted |
| Event/queue | Outbox rows canonical; queue carries delivery/work pointer | Do not rely on queue as audit ledger; managed durable queue when needed |
| Analytics | Aggregated minimized event store/warehouse | Separate access and retention; approve data region before export |
| AI context | Conversation/task records with minimized content and retention controls | Relational metadata; encrypted restricted content only if justified; no vector DB initially |

## Schema ownership and integrity

Use separate PostgreSQL schemas (e.g. `iam`, `user_data`, `catalog`, `orders`, `bookings`, `finance`, `support`, `ai`, `platform`). Each module has separate migration role and repository. Cross-schema joins in application code are forbidden; cross-domain projections are explicit. Foreign keys enforce same-owner aggregates and selected stable references; do not cascade-delete financial/audit history.

IDs are opaque UUID/ULID-class values; decision pending workload/team. Money uses integer minor units + ISO 4217 currency. Time uses UTC instants plus explicit IANA zone for local appointments. High-contention availability uses atomic conditional writes/unique exclusion constraints where feasible, not check-then-write races.

## Migrations and retention

Expand-migrate-contract: add nullable/new structures, dual-read/write temporarily if necessary, backfill idempotently, verify, then remove old fields in later release. No destructive migration with running older app. Separate PII/financial retention schedules. Soft delete is for reversible user-facing entities (profile/listing), not universal: transaction/audit entries remain immutable and access-restricted; personal data may be pseudonymized/deleted only under approved legal retention rules. Backup expiration must match retention/deletion obligations.

## Indexing, partitioning and recovery

Candidate indexes: unique normalized verified phone per identity policy; `catalog(listing_status, category_id)`; PostGIS GiST on service area/point; `orders(customer_id, created_at desc)`, `orders(partner_id,status,created_at)`; `bookings(resource_id, starts_at)` with conflict-safe constraint; `payments(provider_ref)` unique when provided, `ledger(transaction_id, created_at)`; outbox `(published_at, created_at)`; notifications `(recipient_id, created_at desc)`. Validate via EXPLAIN/load tests. Partition only append-heavy event/audit/ledger after evidence and legal review. Recovery objectives are provisional in 23.
