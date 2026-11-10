# Database & Migrations

PostgreSQL JDBC and Flyway are configured. `V1__create_domain_schemas.sql` creates owner namespaces (`identity`, `profile`, `marketplace`, `transactions`, `payments`, `support`) and no user, payment, order or catalog records. This is non-destructive and establishes ownership only. Flyway schema history records migration state.

Local runs require URL and credentials by environment variable. Flyway runs before readiness. PostgreSQL readiness appears in Actuator. No test or production data fixtures are created. This change only creates schemas; rollback is a forward compensating migration, not a schema drop. Future domain migrations must document expand/contract compatibility, owner, constraints/indexes, retention class and recovery plan.

Verification on 2026-11-10 used a uniquely named temporary Compose project and volume with PostgreSQL 16.15 and generated local-only credentials. Spring context connected successfully; Flyway applied V1, the six namespaces and successful `flyway_schema_history` row were asserted, and a second `flyway.migrate()` ran zero migrations. Readiness reported `UP`. This was a temporary verification database, not a shared or production database.

Production region, encryption/KMS, retention and restore objectives are not configured; D-08 and D-12 block production data.
