# 20 — Release & Deployment Strategy

| Channel | Entry criteria |
|---|---|
| Internal builds | Reproducible signed build, dev/test configuration, synthetic data and feature flags |
| QA | PR/merge gates passed; test APIs and provider sandboxes; defects triaged |
| Alpha | Stable core flow with staff/test accounts; observability and rollback/pause controls |
| Closed beta | Approved category/terms and cohort; staffed support; no critical security/data issues; transaction rehearsals passed |
| Open beta | Closed cohort meets operational and quality thresholds established before pilot; capacity and pause thresholds set |
| Production | Legal/finance/operations/security sign-off, supply coverage, backups, alerts/on-call and staged rollout evidence |
| Hotfix | Impact triaged, narrowly scoped reviewed change, targeted regression, recorded expedited approval and post-release watch |

Feature flags must be server-enforced for sensitive category, zone and transaction controls; flag-off behavior must preserve active-order support. Database follows expand-migrate-contract. APIs are versioned and backward-compatible for supported older mobile releases; deprecation is measured and communicated. Roll back app/config when safe; use forward fixes for irreversible data transitions, with compensation/reconciliation for financial effects. Never “rollback” provider money movement by deleting audit history.

Promotion is gated by feature/task acceptance, test evidence, telemetry, runbook, owner, error budget/SLO policy and decision approvals. Release artifacts are immutable and traceable to source and migration version.

