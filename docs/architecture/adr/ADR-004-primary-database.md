# ADR-004: Primary Transaction Database

- **Status:** Proposed for review
- **Context/problem:** KUNDE needs relational marketplace data, immutable transaction links, capacity constraints, and geo lookup.
- **Options:** PostgreSQL; MySQL; polyglot NoSQL stores.
- **Evaluation:** PostgreSQL supports relational constraints, transactions, JSONB for bounded extensions and PostGIS. MySQL is viable but geo/search integration may be less unified. NoSQL adds modeling/consistency cost without a proven key-value workload.
- **Decision:** Recommend PostgreSQL as canonical transactional store; add PostGIS extension after region/provider verification.
- **Consequences:** One DB simplifies ACID/outbox; module schemas/roles prevent shared ownership. Monitor connection/query pressure.
- **Risks:** Managed PostgreSQL/PostGIS availability and legal region evidence are unknown; shared cluster is common failure domain.
- **Revisit when:** Workload, data isolation, residency or availability demands require separate stores/cells.
