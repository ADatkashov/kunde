# KUNDE project state

## Current verified main snapshot — 2026-11-12

- Latest verified merge: `af61a2e586db2bed382677fad4aa5be869a5d99a` (PR #25).
- PR #23 / ADA-73: protected Consumer consent API, Flyway V4 ledger,
  approval-only policies, owner-scoped immutable grant/withdrawal history,
  active-user row lock; merged as `6d098c5`. Backend/Security/config CI green.
- PR #24 / ADA-74: Flutter authenticated consent management with RU/KK/EN,
  confirmation, fail-closed session behavior and tests; merged as `f85c7e0`.
  Flutter/Security/config CI green.
- PR #25 / ADA-76: Flutter saved addresses, manual WGS84 input,
  optimistic delete conflict handling, honest serviceability state and tests;
  merged as `af61a2e`. Flutter/Security/config CI green.
- Linear ADA-73, ADA-74 and ADA-76 remain **In Progress** where acceptance
  remains incomplete: legal/privacy policy approval, consent withdrawal effects,
  policy presentation, native accessibility, real zone/map UX and device checks.
  Do not infer Done from merged PRs.
- Next critical verification is ADA-72 / TASK-006: **native** refresh replay,
  provider outage/recovery, expiry, iOS, TalkBack/large text, physical devices
  and account session administration. Protocol and unit tests are not native proof.
- GHSA-r937 remains unresolved; no scanner suppression or production sign-off.
- The paragraphs below are retained as historical evidence and must not be read
  as the current main commit or current test count.

- PR #27 (ADA-72) is merged (`b91cad0`): provider network outage/recovery probe only.
- PR #28 (ADA-72, draft) extends the Android35/Chrome124/AppAuth/Keycloak native harness.
  Hosted run 43270980722 (source `5159ae7`) passed with 17 completed checks, adding:
  provider outage **during refresh** with recovery, rotated refresh-token **replay**
  rejected natively (session cleared), same-canonical-account relogin, expired access
  token refreshed natively (real 310 s wait; no clock manipulation) and no JWT material in
  device log or plaintext vault file. Sanitized artifact `identity-e2e-sanitized` is retained.
  Merge, CodeRabbit review and required CI on PR #28 are not yet confirmed. TASK-006 stays
  in_progress; NOT_EXECUTED: iOS, TalkBack, large text, full RU/KK journeys, physical devices,
  account session administration (API returns 503). GHSA-r937 remains open.
- Linear ADA-72/ADA-73 were found in Done and returned to In Progress on 2026-11-12.

## Historical engineering notes

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
