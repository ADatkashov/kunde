# KUNDE project state

Reviewed 2026-11-12. Follow AGENTS.md; code and current CI are authoritative.

- Main bb5619b includes merged PRs #11–#12: bounded peer-IP admission and request
  body guard before JWT/controllers. Main hosted Backend 57/Flutter 33 and APK/native
  checks pass; SDK tooling remains red. See those PRs for exact evidence.
- Current TASK-046 branch adds post-JWT per-process `(issuer, subject)` budgets:
  token rotation, peer changes and caller identity/device headers cannot reset them.
  Cloud Java 21/PostgreSQL16.15 clean verify passes 68 tests with no failures/skips;
  signed-JWT/JWKS HTTP and existing packaged JAR smoke pass. This branch evidence
  does not claim live IdP/native/device E2E or production readiness.
- TASK-045 is partially_verified after a documented technical threat/default review;
  formal privacy/production threat, operations and audit coverage gates remain open.
  TASK-046 and TASK-006 stay in_progress. All 56 canonical TASK IDs are preserved.
- Stack: Java 21 / Spring Boot 4.0.9, PostgreSQL/Flyway V1–V2, Flutter 3.47.9.
- ADR-015 accepts Keycloak primary/ZITADEL fallback for synthetic development.
  Production privacy/residency, legal, OTP, operations and recovery gates remain open.
- Consumer identity owns canonical UUID/issuer-subject binding, lifecycle checks and
  optimistic profile updates. The new quota does not link IdP aliases or replace
  business authorization. Flutter has real AppAuth/PKCE/secure-vault flows; account
  session administration is still 503. PR #5's provider protocol fixture is not native
  Consumer browser/vault/accessibility proof.
- SDK GHSA-r937 remains open (two MODERATE matches in observed tooling graphs).
  Owner permitted merges #11 and #12 with this known finding; no production approval
  or scanner suppression follows. Trusted device, canonical-account-wide and
  distributed-edge/read-timeout/concurrency controls still need their contracts.
- Missing native scenario prerequisites make the manual E2E gate fail with
  NOT_EXECUTED evidence. Next controlled verification work is TASK-006's actual
  isolated Android system-browser scenario. See NEXT_TASK.md and
  [security evidence](docs/security/TASK-046.md),
  [technical baseline](docs/engineering-foundation/authentication-and-security.md),
  [Consumer fixture](docs/identity/consumer-validation/README.md).
