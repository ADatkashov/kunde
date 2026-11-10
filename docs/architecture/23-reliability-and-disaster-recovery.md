# 23 — Reliability and Disaster Recovery

## Failure design

Provider calls use connection/read deadlines, bounded retry with jitter, circuit breaker and per-provider bulkhead. Retry only idempotent calls or calls with provider idempotency reference. Unknown payment is reconciled, not assumed failed. Search/map/AI outages degrade browse/assistant features; core order status and payment journal remain available. Outbox retains work until acknowledged or dead-lettered.

## Recovery model

- Proposed RPO ≤15 minutes and RTO ≤4 hours for transactional data are initial planning targets, not approved SLOs; validate with local-region replication, cost and legal rules.
- PostgreSQL PITR and encrypted backup; object versioning/lifecycle where appropriate; restore into isolated region-approved environment and validate checksums/domain invariants.
- Recovery runbooks cover DB restore, key rotation, provider outage, queue replay, payment reconciliation, compromised credentials and accidental release.
- Failover must preserve single-writer ownership per regional customer/financial partition. Prevent split brain with fencing and explicit region authority.
- Backups/logs/replicas remain in approved jurisdiction unless legal review authorizes otherwise.

## Incident objectives

Severity, escalation, on-call ownership, customer communication and regulator notification timelines require operations/legal definition. Finance integrity mismatch is a high-severity incident. Test restore and runbooks before public transactions and after major infra changes; record result and remediation.
