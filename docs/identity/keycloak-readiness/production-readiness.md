# Production-readiness assessment

The local drill validates a narrow Keycloak and Spring integration. Release readiness depends on completing the staged exercises below and the [operational requirements](operational-requirements.md).

| Gate | Status | Exit evidence |
|---|---|---|
| Provider and operating owner | Open | Explicit ADR-015 acceptance, named security and operations owners, patch and incident coverage, approved fallback |
| PostgreSQL and restore | Local persistence only | Approved PostgreSQL topology and encrypted backups. Restore Keycloak, configuration, signing keys and secrets in an isolated environment. Measure RPO and RTO. |
| HA, upgrades and disaster recovery | Open | Demonstrate component and zone failover, mixed-version compatibility or downtime plan, tested restore-based rollback and operations handoff |
| Proxy, TLS and secrets | Open | Verify exact issuer through trusted forwarding headers, HTTPS only, isolated admin/management routes, certificate renewal and secret rotation |
| Monitoring, audit and capacity | Open | Load normal and burst login/refresh, size JVM and PostgreSQL, set alerts and run an incident drill with redacted logs |
| User migration and recovery | Open | Rehearse mapping, collision, credential and session handling with synthetic data. Verify support recovery and provider exit. |
| Kazakhstan processing | Open | Counsel signs the region, data-flow, transfer, retention and subprocessor assessment for databases, replicas, backups, support, logs, telemetry and OTP |
| SMS/OTP | Open | Verify IdP-owned challenge lifecycle, contracted transactional route, rate/spend caps, delivery status and abuse controls using synthetic data |

Use the [current Keycloak production guide](https://www.keycloak.org/server/configuration-production), [upgrade guide](https://www.keycloak.org/docs/26.8.2/upgrading/) and [KUNDE privacy design](../privacy-and-compliance.md) during review.
