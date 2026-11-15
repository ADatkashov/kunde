# KUNDE project state

## Current verified main snapshot — 2026-11-13

- **DEV deployed (2026-11-14, owner-approved applies, synthetic data only):** Terraform (`infrastructure/terraform`, PRs #71–#75) manages Render Free `kunde-backend` (Frankfurt, https://kunde-backend-5wwg.onrender.com) and Neon Free `kunde-dev` (`aws-eu-central-1`); state in HCP Terraform workspace `kunde-dev`; GitHub Actions `terraform-dev.yml` (validate, plan, cost gate `check_terraform_plan.py`, manual apply). Verified on the live service: `readiness`/`liveness` 200, protected endpoint 503 (fail-closed), OpenAPI 200, `GET /api/v1/categories` 200 `[]`, Flyway V1–V8 over TLS (`verify-full` + `DefaultJavaSSLFactory`). Known limits: Render provider 1.9.1 cannot update free services in place (issue #80) — changes need `replace_render`; free hours are shared with the owner's 6 other Render services and Neon Free has 100 CU-hours/month (cost not confirmed as $0); cold start ~1 min; Required reviewers on the `dev` Environment are **not** configured (apply ran without a pause). Production hosting/residency still blocked (TASK-051/D-08); TASK-052 stays not_started (no prod staged deploy/rollback); ADR-017 Proposed. Docs: [docs/infrastructure](docs/infrastructure/README.md).

- **Own phone-OTP authentication (2026-11-14, owner decision, merged in PR #80 `4a21db1`; ZITADEL draft PR #79 closed unmerged):** ADR-015 amended — no Keycloak/ZITADEL/external IdP; Spring Boot issues OTP-verified access JWT + rotating refresh tokens (`/api/v1/auth/otp/request|verify`, `/auth/token/refresh`, `/auth/logout`, Flyway V9, `OtpDeliveryProvider`). Off by default (`AUTH_PHONE_ENABLED`); DEV code `123456` only for allowlisted synthetic `+7700000XXXX` numbers in `KUNDE_ENVIRONMENT=dev|local|test` (startup aborts otherwise). No SMS/WhatsApp provider connected (D-11). Flutter phone/OTP screens behind `PHONE_AUTH_ENABLED`; profile/consents/addresses unchanged. Local: backend 200 tests pass on PostgreSQL 16, Flutter `analyze --fatal-infos` clean and 128 tests pass; no device run, nothing applied to Render/Neon (needs owner secret `AUTH_PHONE_SECRET` + approved Terraform apply). Production use gated (independent security review, OTP vendor, privacy/residency, key management). Docs: [phone-otp-auth](docs/identity/phone-otp-auth.md), [ADR-015](docs/architecture/adr/ADR-015-proposed-identity-provider.md).

- **DEV Android Release APK (2026-11-14, PR #77, `640add3`):** manual workflow `android-release.yml` builds a signed `flutter build apk --release` (arm64) against the Render API (`API_BASE_URL`, `API_TIMEOUT_SECONDS=90` for cold start). Signing only from GitHub secrets `ANDROID_KEYSTORE_BASE64/_PASSWORD`, `ANDROID_KEY_ALIAS/_PASSWORD` (owner-generated DEV key kept outside Git; no debug fallback). Run 43619187983 succeeded (analyze, test, signature/appId/INTERNET/non-debuggable/arm64/API-URL/no-secret checks; artifact `KUNDE-dev-release`, 14 days). Owner installed it on a Samsung phone; no functional phone checks reported yet. Before the phone-OTP PR this build had identity off (no IdP in DEV), so protected screens were unusable; applicationId is still `com.example.kunde_mobile`. Docs: [android-release-apk](docs/infrastructure/android-release-apk.md).

- **TASK-016 in_progress (merged: #81 `217f7a9`, #82 `7a7c243`, 2026-11-14):** Flyway V10 `marketplace.offerings.partner_id` (PUBLISHED requires a partner, DB check); consumer offering list/detail/search join APPROVED partners only and return `partnerId`/`partnerName`; public `GET /api/v1/partners/{id}` (APPROVED only, otherwise `404 PARTNER_NOT_FOUND`); Flutter search shows the partner name. Migrations seed no partners (test-guarded) — DEV catalog stays empty per ADR-014. Backend 203 tests pass on PostgreSQL 16 and required CI was green on both PRs. Missing: partner-scoped write/authorization API (needs partner-app audience and admin identity, D-14), price/availability (D-03/D-04, TASK-022/014), device checks. Linear synced 2026-11-14: ADA-79/80/87/97/107/114/116/122 moved Todo → In Progress to match the backlog (none are Done). Owner decision drafts: [D-03/D-04](docs/product/decision-drafts/P1-decisions-D-03-D-04-payments-commission.md).

- TASK-015 **in_progress**: partner persistence (Flyway V8 `marketplace.partners/partner_staff/*_events`, `PartnerService`): D-07 roles, partner isolation, revocation,
  append-only audit, verification gate (`mayProcessOrders` needs active staff + APPROVED). No HTTP API, documents/KYC or catalog link. Backend 164 tests pass locally against
  PostgreSQL 16 (155 existing + 9 new; temporary local cluster with synthetic credentials).

- **D-05/D-06/D-07 APPROVED (2026-11-13, Product Owner):** restaurant response 5 min / reminder 2 min / auto-timeout; free cancel before acceptance, no
  invented penalties or refunds; partner roles Owner/Manager/Operator + KUNDE Administrator with manual verification. Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md).
  TASK-021 blocked → in_progress (contract-only `OrderLifecycle`, 16 unit tests; no persistence/API/scheduler/payment link). TASK-027/028 stay blocked (D-03/D-04, D-14);
  D-03, D-04, D-08–D-15 unchanged. Backend: 88 non-DB tests pass locally; the 67 Spring/PostgreSQL tests were not run here (no DB credentials) and rely on CI.

- **D-02 APPROVED (2026-11-13, Product Owner):** phased hybrid fulfillment for Food Ordering (A pickup, B merchant delivery, C third-party logistics; no KUNDE courier
  fleet at start). Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md). TASK-019/029 moved blocked → in_progress (not Done); TASK-020/030 unchanged;
  D-03–D-15 unchanged. PR #63 (V7) added only the unpublished DRAFT `food-ordering` category.

- **D-01 PARTIALLY APPROVED (2026-11-13, Product Owner):** first category Food Ordering, first market Almaty. Cohort (8–12 restaurants), pilot zone and
  50–100 users are proposals only; D-02–D-15 unchanged. Record: [PRD 1.1 §23](docs/product/PRD-1.1/23-assumptions-and-open-decisions.md). ADR-014 unchanged
  (catalog stays empty/non-orderable). Docs only; no task status changed. PR #61 (TASK-012) is merged with required CI green.

- **Home screen redesign (owner-approved visual reference, 2026-11-13):** Flutter `HomeScreen` is now the Super App home (header with Almaty chip, search,
  KUNDE AI card, 10-tile category grid, Food banner, quick actions, "Рядом с вами" empty state). Only Food is a first category and is active
  only when `marketplaceEnabled`; all other categories, AI, quick actions are explicit "Скоро"/disabled (no orders, no demo restaurants/ratings/times,
  no payments/delivery). Reference's 5-tab bottom bar (Главная/Поиск/Заказы/Избранное/Сервисы) differs from
  [docs/design/07](docs/design/07-consumer-app.md) — resolved by owner decision 2026-11-13: four tabs Главная/Поиск/Заказы/Профиль (DS-04), AI stays a Home block;
  Search/Orders/Profile show honest empty states without their capability; PRD-1.0 §navigation still says five (owner to update); no bell/profile
  icons (no backend); no photo assets (Material icons). Category grid is 5 columns from 360 px with muted "Скоро" tiles. `flutter analyze` clean, 113 `flutter test` pass locally; no device/TalkBack check.

- Latest verified merge: `ab001ac18ec7dd98986aa77d67fb36f3970ed693` (PR #41).
- PRs #29–#37 (merged after #28), all with required CI green:
  #29 state/backlog sync; #30 TASK-055 domain schema ownership tests; #31 TASK-047
  correlation/log/Actuator tests; #32 TASK-053 secret-marker gate tests; #33 TASK-013
  Flyway V5 `marketplace.categories/offerings`; #34 owner standing merge permission
  (see AGENTS.md); #35 TASK-011 published-category search; #36 TASK-012 Flutter
  category search panel; #37 TASK-014 `GET /categories/{id}/offerings` (PUBLISHED
  only; no price, partner or availability).
- PRs #38–#41, all with required CI green: #38 state sync; #39 TASK-014 `GET /offerings/{id}`
  (404 `OFFERING_NOT_FOUND` unless PUBLISHED in a PUBLISHED category) and paginated offerings
  list (`limit`<=100, `offset`); #40 TASK-041 closed 27-event catalog and data-minimization
  validator (`EventCatalog`, contract only, nothing emitted or stored; see
  docs/engineering-foundation/event-taxonomy.md); #41 TASK-050 `KundeFormats.money`
  (integer minor units + ISO code, ru/kk/en; Flutter CI ran its tests, not a device).
- PRs #43–#46, all with required CI green: #43 TASK-010 explicit default-deny serviceability
  status in the address panel; #44/#45 backlog JSON fix and CI backlog validation; #46 TASK-008
  consent panel shows one row per policy in the reader's language (fallback order kk → ru → en,
  owner decision 2026-11-13) and states that policy text is not in the app yet. TASK-008 stays
  **in_progress** (needs approved policy text/link, TASK-007 legal wording, TalkBack/device checks).
- PRs #47–#49, required CI green: #47 state sync and Russian-language rule in AGENTS.md; #48 TASK-056
  local synthetic restore drill (`scripts/ci/restore_drill.sh`, not in CI, not production backup evidence);
  #49 TASK-048 draft incident runbook for existing signals (unapproved, no owners/SLOs). TASK-056 and
  TASK-048 are **in_progress**, not Done.
- TASK-015 **in_progress**: contract-only `PartnerVerification` state machine (draft PB-01/PB-02; no persistence, API,
  partner roles or catalog activation; ADR-014 unchanged). Backend unit tests only.
- TASK-037 **in_progress**: backend consumer support cases (Flyway V6, `/api/v1/me/support/cases`, idempotent create, owner-scoped reads,
  escalation request; see docs/engineering-foundation/api-contracts.md). No transaction link, staff side, SLA or notifications (D-11/D-12/D-14
  open); backend merged as PR #57 (`c70d783`).
- TASK-011/014 **in_progress**: `GET /api/v1/search/offerings` (published-only, ranked, paginated; public path added to security config; Backend 121 tests pass locally). Flutter search panel now shows published offerings too (77 `flutter test` pass locally; no device check).
- TASK-054 **in_progress**: backend concurrency/recovery tests for provisioning and support cases (found and fixed a support-case cap race);
  not the pilot E2E suite. Backend 119 tests pass locally (POC JWT test needs its own DB, not run).
- TASK-038 **in_progress**: Flutter `SupportPanel` on the profile screen (list/open/escalate, RU/KK/EN); `flutter analyze` and 73 `flutter test` pass locally; no device/TalkBack run. Backend 115 tests pass locally against PostgreSQL 16 (POC JWT test needs its own DB, not run).
- TASK-031 **in_progress**: contract-only `NotificationPolicy`/`Delivery` (PRD 1.1 §14); no provider (D-11), outbox,
  persistence or sending. Backend unit tests only.
- Catalog tasks TASK-011/012/013/014 remain **in_progress**: no seed data, offering search,
  price, partner link, serviceability or availability rules; ADR-014 (no default orderable
  catalog, `marketplaceEnabled=false`) still applies. TASK-041 and TASK-050 are also
  **in_progress**, not Done: analytics has no consent/residency/outbox/KPI approval and
  localization has pure plural/date/time helpers (unapproved layout) but lacks time-zone conversion, address/phone formats and approved critical copy (TASK-049).
- Earlier snapshot, retained as history: PR #25 (`af61a2e`).
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
- PR #28 (ADA-72) is merged (`5de3184`, 2026-11-12) and extends the Android35/Chrome124/AppAuth/Keycloak native harness.
  Hosted run 43270980722 (source `5159ae7`) passed with 17 completed checks, adding:
  provider outage **during refresh** with recovery, rotated refresh-token **replay**
  rejected natively (session cleared), same-canonical-account relogin, expired access
  token refreshed natively (real 310 s wait; no clock manipulation) and no JWT material in
  device log or plaintext vault file. Sanitized artifact `identity-e2e-sanitized` is retained.
  Required CI (configuration, dependencies, containers, secrets) passed; CodeRabbit did not
  review (manual trigger only) and the merge was owner-approved. TASK-006 stays in_progress; NOT_EXECUTED: iOS, TalkBack, large text, full RU/KK journeys, physical devices,
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
