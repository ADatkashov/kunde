# KUNDE project state

Reviewed 2026-11-12. Follow AGENTS.md; code and current CI are authoritative.

- Reconciled main 4595309 after PR #5 merge: Backend/Flutter/APK/configuration
  runs 43078224891/43078224810/43078224874/43078224746 succeeded. All 56 existing
  backlog tasks now have explicit states; no epic/release completion inferred.
- TASK-003 native prerequisite gate now fails on missing scenario files and
  retains NOT_EXECUTED evidence; regression tests run in configuration CI.
  Hosted evidence for this increment is tracked in its PR. SDK vulnerability
  and native Consumer E2E remain open.

- TASK-046 branch increment (2026-11-12): bounded per-process API peer-IP quota,
  429/Retry-After, aggregate denial metric and forwarded-header rejection added.
  Cloud Java21/PostgreSQL16 clean verify passes 47 tests with no skips, including
  real HTTP and concurrency checks. Hosted evidence will be recorded in its PR.
  Account/device/edge quotas, body-size controls and SDK advisory remain open.
- Main advanced externally to 1d367bf: PR #7 merged as397676d, plus APK preview
  publication, CodeRabbit configuration and repository-wide Security CI (PRs8–10).
  Those changes are preserved in this branch integration. This task did not merge
  PR #7 after automatic approval review rejected it for the SDK security failure.

- Java 21 / Spring Boot 4.0.9, PostgreSQL/Flyway V1–V2 and Flutter 3.47.9 (updated in main).
- ADR-015 is ACCEPTED for synthetic implementation: Keycloak primary, ZITADEL
  fallback. Production readiness, privacy, residency, operations and OTP remain gated.
- PRs #1–#3 added hosted CI, Consumer Identity/Profile and tests. Main at 22c1ae8
  had Backend/Flutter CI failures; PR #5 fixes Method Security 500s and formatting.
- Consumer /me provisions an immutable UUID from verified issuer/subject, enforces
  restricted status, scopes/client/token type and profile version. Sessions API
  explicitly returns 503 pending implementation.
- Flutter has real AppAuth browser authentication, secure token vault, serialized
  refresh/logout, splash/restore, RU/KK/EN welcome/home/profile editing and errors.
  Enable only with explicit development configuration; no production mock login.
- Current local verification: 40 backend tests with PostgreSQL and 33 Flutter tests;
  formatter/analyzer and packaged smoke passed. Real Keycloak protocol registration,
  PKCE, profile, refresh/replay, logout and subsequent login passed with synthetic
  data. This is not native browser/device E2E. See the reproducible
  [verification package](docs/identity/consumer-validation/README.md).
- Remote workflow results and merge status are recorded in PR #5. Earlier CI and
  POC evidence remain historical; they do not establish production readiness.

- Main advanced during PR #5 development to d929853, including owner-authorized
  PR #4 and its supported Boot 4/container/native remediation. Those changes,
  security regression tests and protected Bearer-header test are preserved in
  the integration merge. The combined tree passes 40 backend and 33 Flutter tests locally;
  PR #5 records fresh hosted results.
- PR #4 verified digest-pinned Temurin 21 UBI10/Maven 3.10 container builds/scans,
  native dependency OSV zero, Maven/Pub/build roots zero and Gitleaks. The upstream
  Flutter SDK audit still has two MODERATE matches of GHSA-r937-wjx7-w2jp in Kotlin
  tooling. Security CI is not globally green. TASK-003 remains partially_verified;
  TASK-006 and TASK-046 remain in_progress. See the
  [security ledger](docs/security/ci-vulnerability-ledger.md),
  [runbook](docs/security/security-runbook.md) and [TASK-046](docs/security/TASK-046.md).
  API abuse controls and distribution/native-binary audit coverage remain open.
