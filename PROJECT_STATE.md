# KUNDE project state

Reviewed 2026-11-12. Follow AGENTS.md; code and current CI are authoritative.

- ADA-72 PR #17 merged as afdab129 (2026-11-12). Hosted Android native E2E
  run 43219354337 succeeded with prerequisites and emulator jobs; the registration
  harness extends six prior checks to eleven. Sanitized CI artifact is retained.
  TASK-006 remains in_progress: replay, outage/expiry, iOS, accessibility,
  physical-device and session-administration evidence are still missing.

- Owner requested essential automatic CI: configuration, scoped backend/Flutter,
  and dependency/secret/container security checks. APK, SDK tooling and diagnostic
  workflows are manual; their evidence/DoD requirements remain. See
  docs/engineering-foundation/github-hosted-ci.md. GHSA-r937 remains OPEN.

- Main 51374d1 includes PRs #11–#13: bounded peer-IP admission and request body
  guard before JWT/controllers, followed by verified `(issuer, subject)` quotas.
  Backend 68/Flutter 33 checks pass; SDK GHSA-r937 remains open.
- TASK-006 PR #14 verifies six targeted native checks on source db13a26:
  Android35/Chrome124.0.6367.219 system-browser login/PKCE callback, profile edit,
  two vault/rotated-refresh restores, API offline retry, provider logout/relogin,
  plus welcome RU/KK/EN. Hosted run 43209945677 succeeds; sanitized report is
  retained in docs/identity/consumer-validation/native-evidence-2026-11-12.json.
  Fourteen local Python tests and separate Cloud Chromium S256/API checks pass.
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
- Native scenario prerequisites now exist on PR #14. The manual gate requires six
  executed checks and keeps all remaining native/device/accessibility gaps explicit.
  TASK-006 remains the next controlled verification task. See NEXT_TASK.md,
  [security evidence](docs/security/TASK-046.md),
  [technical baseline](docs/engineering-foundation/authentication-and-security.md),
  [Consumer fixture](docs/identity/consumer-validation/README.md).
