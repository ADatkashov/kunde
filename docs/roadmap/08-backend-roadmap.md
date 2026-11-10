# 08 — Backend Implementation Roadmap

Follow the modular Spring Boot architecture and domain boundaries in `docs/architecture/`; this is sequencing, not a stack or API change.

| Sequence | Work and readiness evidence | Dependencies / verification |
|---|---|---|
| 1 | Repository/build conventions, configuration profiles, health endpoints, OpenAPI generation/version policy | Architecture sign-off; clean build, config validation |
| 2 | Security filters, identity/session adapter, scoped authorization, rate limits, audit primitives | First complete [EP-002 design and decision gates](25-identity-ep002-design.md); D-05/D-07 and accepted provider choice; authz negative tests, threat review |
| 3 | PostgreSQL schema ownership, migration runner, constraints, seed/reference data | Domain model and D-08; migration forward/compatibility tests |
| 4 | Profile, address/serviceability and localized catalog read modules | D-11/D-15; unit/integration/API contract tests |
| 5 | Partner, branch, catalog and availability workflows | D-01/D-07; permission and operational scenario tests |
| 6 | Order/booking state machine, idempotent commands, transactional outbox and audit | D-01/D-05/D-06; state transition, duplicate and rollback tests |
| 7 | Payment/fulfillment provider ports and sandbox adapters; verified event/status reconciliation | D-02/D-03/D-04; contract, signature, replay, timeout and reconciliation tests |
| 8 | Support/admin APIs, scoped RBAC and approval controls | D-14, finance/security review; audit and separation-of-duty tests |
| 9 | Notifications and background jobs with retry/dead-letter policy | D-11, consent; duplicate/out-of-order delivery tests |
| 10 | Production dashboards, alert/runbook links, backup/restore and failure rehearsals | D-12, hosting; recovery exercises and load profile |

Domain modules own their entities and writes; shared kernel must not become a second owner of business state. Publish events through an outbox only where consumers require durable asynchronous work. Keep payment/order state separate and reconcile provider truth. No direct AI-to-database or AI-to-ledger path.

Identity-specific design, provider-selection gates and implementation dependencies are in [25-identity-ep002-design.md](25-identity-ep002-design.md). Current issuer/audience validation is a foundation; it is not user lifecycle implementation.

