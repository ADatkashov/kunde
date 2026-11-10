# 12 — Database & Data Migration Roadmap

Use the architecture's PostgreSQL/PostGIS recommendation, subject to verified hosting/residency. Each domain module owns its tables and migrations; cross-module writes occur through explicit contracts/events, not direct repository access.

## Order of work

1. Database provisioning, roles, encryption/backup, environment separation and migration automation.
2. Reference/identity/profile/address tables with documented owner and retention class.
3. Partner, branch, category, catalog, price and availability tables with constraints and indexes.
4. Order/booking lifecycle, line snapshots, idempotency keys and immutable audit/event records.
5. Payment attempts, provider references, reconciliation evidence and refund records with restricted access.
6. Support/notification/analytics data minimization and retention/deletion rules.
7. Query/index tuning from measured pilot traffic; backup restore and failure recovery rehearsal.

## Migration and ownership rules

Use forward-only versioned migrations in CI; review destructive changes separately. Apply expand → backfill → dual-compatible reads/writes if needed → contract only after supported clients/workers have moved. Never deploy a schema change that requires all mobile clients to update simultaneously. Seed only non-sensitive reference/demo data. Define PII/financial/audit retention and deletion exceptions with legal/privacy before production (D-08); encrypt sensitive fields/storage and restrict backup access. Restore tests record achieved recovery objectives against approved D-12 targets.

