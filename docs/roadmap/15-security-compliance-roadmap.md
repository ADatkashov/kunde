# 15 — Security & Compliance Roadmap

## Before MVP implementation touches real data/money

Resolve role assurance and data handling (D-07/D-08); threat model checkout, identity, partner/admin and provider boundaries; define RBAC/least privilege, session revocation, secret handling, encryption, API validation, rate limits/abuse controls, audit and PII minimization. Review payment scope and legal role before choosing a flow. Add security checks to CI and incident/credential compromise procedures.

## Before closed transactional pilot

Complete authorization-negative tests, dependency/image scanning and remediation policy, sensitive-data/log review, webhook signature/replay protection, idempotency/reconciliation controls, admin separation of duties, privacy/consent review, backup protection, vulnerability response ownership and scoped penetration/security testing appropriate to exposure. Sign off residual critical/high risks.

## Later and continuous

Fraud analytics, advanced device signals, privacy-preserving personalization, recurring access reviews, deletion/retention automation and expanded penetration tests evolve with threat and market evidence. Family/child, health/pharmacy, cross-border processing and proactive AI require specialist review before design or launch. Security controls must not be bypassable through AI tools, internal APIs, debug endpoints or admin overrides.


## Executed TASK-046 increment — 2026-11-11

Supported Boot4 BOM/project Android remediation and maintained immutable/effective containers eliminate observed CRITICAL/HIGH. See [ledger](../security/ci-vulnerability-ledger.md). SDK MODERATE, binary/tool distribution coverage and missing API abuse controls keep TASK-046 in_progress. TASK-006 in_progress; no Consumer native E2E/production claim. Next independent security work is supported upstream tooling remediation and scoped abuse controls. PR1 externally merged; later branch commits need separate review.


### Main integration review — 2026-11-11

Main22c1ae8 now publishes Consumer canonical identity/profile, issuer/subject binding, FlywayV2, Consumer authorization and Flutter auth repository/tests. Earlier statements that these modules were absent describe the historical baseline only. Preserve these additions; do not replace them with the older branch. Owner explicitly authorized integration/merge through PR4. Combined-source checks are required; native Consumer E2E and API abuse controls remain open. TASK-006/TASK-046 stay in_progress; no production readiness.
