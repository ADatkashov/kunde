# KUNDE project state

Reviewed 2026-11-12. Follow AGENTS.md; code and current CI are authoritative.

- Main 5e8c182 includes merged PR #11: bounded per-process peer-IP API quota,
  correlated 429/Retry-After, aggregate denial metric, CORS and encoded-path fixes.
  Its verified source passed 47 backend tests and 33 Flutter tests; see PR #11.
- Current TASK-046 body-limit increment is a branch change based on that main.
  Cloud Java 21/PostgreSQL16.15 clean verify passes 57 tests with no failures/skips.
  Known/unknown/chunked lengths are bounded before JWT/controllers; valid JSON
  bytes and allowed-origin CORS are preserved. Hosted evidence belongs in its PR.
- Stack: Java 21 / Spring Boot 4.0.9, PostgreSQL/Flyway V1–V2, Flutter 3.47.9.
- ADR-015 is ACCEPTED for synthetic development: Keycloak primary, ZITADEL fallback.
  Production privacy/residency, legal, OTP, operations and recovery gates remain open.
- Consumer /me owns a stable UUID mapped uniquely from verified issuer/subject,
  restricted-account checks, consumer claims and optimistic profile versioning.
  Flutter uses real AppAuth/PKCE, secure vault, serialized refresh/logout and
  localized restore/welcome/home/profile flows. Session administration remains 503.
- PR #5's synthetic Keycloak protocol checks do not establish Consumer native
  Android/iOS browser, vault or accessibility E2E. See the
  [verification package](docs/identity/consumer-validation/README.md).
- All 56 canonical TASK IDs have explicit states. TASK-003 remains partially_verified;
  TASK-006 and TASK-046 remain in_progress. Account/device/distributed-edge quotas,
  production limits and supply-chain coverage remain open; no release is approved.
- Security CI is not globally green: Flutter SDK tooling retains 2 MODERATE matches
  of GHSA-r937-wjx7-w2jp. Owner explicitly permitted PR #11 merge with that finding;
  the finding remains open and production readiness is not approved. Do not suppress
  the scanner or patch SDK sources. See [TASK-046](docs/security/TASK-046.md),
  [ledger](docs/security/ci-vulnerability-ledger.md) and [runbook](docs/security/security-runbook.md).
- Native E2E gate fails on missing real scenario prerequisites and retains
  NOT_EXECUTED evidence. Repository-wide Security CI, APK preview publication and
  scoped CodeRabbit configuration from PRs #7–#10 are preserved.
