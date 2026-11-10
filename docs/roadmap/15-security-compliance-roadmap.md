# 15 — Security & Compliance Roadmap

## Before MVP implementation touches real data/money

Resolve role assurance and data handling (D-07/D-08); threat model checkout, identity, partner/admin and provider boundaries; define RBAC/least privilege, session revocation, secret handling, encryption, API validation, rate limits/abuse controls, audit and PII minimization. Review payment scope and legal role before choosing a flow. Add security checks to CI and incident/credential compromise procedures.

## Before closed transactional pilot

Complete authorization-negative tests, dependency/image scanning and remediation policy, sensitive-data/log review, webhook signature/replay protection, idempotency/reconciliation controls, admin separation of duties, privacy/consent review, backup protection, vulnerability response ownership and scoped penetration/security testing appropriate to exposure. Sign off residual critical/high risks.

## Later and continuous

Fraud analytics, advanced device signals, privacy-preserving personalization, recurring access reviews, deletion/retention automation and expanded penetration tests evolve with threat and market evidence. Family/child, health/pharmacy, cross-border processing and proactive AI require specialist review before design or launch. Security controls must not be bypassable through AI tools, internal APIs, debug endpoints or admin overrides.

