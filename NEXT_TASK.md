# Next task — owner phone check of Partner Operations on two devices

Install `KUNDE-dev-release` of [run 43927055620](https://github.com/ADatkashov/kunde/actions/runs/43927055620). Customer `+7 700 000 00 01`, partner `+7 700 000 00 02` (code `123456`, second phone or after logout). Customer: Home → Food → «Кухня партнёра (демо)» → order; Services → Beauty → «Барбершоп партнёра (демо)» → book. Partner: Profile → «Партнёрам» → «Заказы, записи и доступность»: accept/prepare/deliver or reject with reason; confirm/reject the booking; availability tab. Customer sees each status (orders poll 4 s, pending booking 5 s); restart the app: history stays. Record results in PROJECT_STATE. Check: `python3 scripts/dev/partner_ops_smoke.py https://kunde-backend-ty81.onrender.com +77000000001` prints `SMOKE OK`.

---

# Next task — owner phone check of Beauty/Barbershop and Home/Cleaning APK

After the category-architecture PR is merged and DEV is redeployed (`BOOKING_SEED_DEMO` seeds the cleaning company; V19 applies), run `scripts/dev/booking_smoke.py https://kunde-backend-ty81.onrender.com +77000000001` (must print `SMOKE OK`) and `food_smoke.py`, then install the signed APK from `android-release.yml`. Phone check: Home → Красота → Барбершопы → book → Orders → Записи → cancel; Home → Дом и быт → Уборка → type, address, area, price, time → request → restart → history → cancel; Food and Grocery still work; RU/KK/EN. Record results in PROJECT_STATE; do not start taxi, medicine or payments. Independent follow-ups: translate Food/Grocery/Partner screens to KK/EN, repeat booking, more Beauty/Home services only after owner scope confirmation.

---

# Next task — verify the premium Flutter Release APK on Samsung

---

# Next task — owner check of the signed premium APK on Samsung

The premium redesign is merged (#98, #99); **178 tests and main CI are green**. Signed ARM64 Release APK: [run 43770508122](https://github.com/ADatkashov/kunde/actions/runs/43770508122), artifact `KUNDE-dev-release` (id `14184357296`, expires 2026-11-29), code `59295d0`. Signature and contents passed workflow verification; downloaded SHA-256 and bundled licenses were checked. DEV API/partner features preserved.

Owner: install over the previous Release APK and check light default with dark system settings, city/search/categories, Food/Grocery → cart → checkout → order → restart/history, Services → booking/cancel, profile/language/logout, 200% text and TalkBack. Record observed results in PROJECT_STATE. No device success is implied by widget/golden/CI tests. Details: [premium UI evidence](docs/design/premium-ui-redesign.md).

---

# Next task — owner phone check of Food, Grocery and Booking; then expand Booking

Food, Grocery (V17) and Booking (V18) are deployed on DEV `kunde-backend-ty81` and pass the DEV smoke scripts (`scripts/dev/food_smoke.py`, `scripts/dev/booking_smoke.py`); the APK is `KUNDE-dev-release` of run 43767173233. Owner: check on the phone (see PROJECT_STATE) and report. Next engineering steps without new decisions: KK/EN texts for Food/Grocery/Booking screens, Booking polish (repeat booking, reminders only as DEV mock), cleaning as the second booking service once the owner confirms its scope (see [booking-mvp](docs/product/booking-mvp.md)).

(Older item kept below.) Deploy KUNDE Food to DEV and verify it on a phone

1. Owner: run *Terraform DEV* (`workflow_dispatch`, `apply=true`, `confirm=apply-dev`, `replace_render=true`) from `main` after the Food PRs merged; DEV then gets `FOOD_ENABLED` + `FOOD_SEED_DEMO`. Replacing the Render service changes its URL: take the new host from the run and pass it as `api-base-url` to *Android Release APK (DEV)*.
2. Check: `python3 scripts/dev/food_smoke.py https://<dev-host> +77000000001` prints `SMOKE OK`; `GET /api/v1/capabilities` has `marketplaceEnabled=true`.
3. Install the APK; sign in `+7 700 000 00 01` / `123456`; Home → Food → restaurant → dish → cart → checkout → order status → restart app → Orders tab shows the order. Record the result in PROJECT_STATE.

Previous priority (kept below): TASK-006 / ADA-72 remaining device/accessibility/session-admin verification.

Last main merge: `86a6c31ea8ea2aa60b9e0af6bddd5968c7315404` (PR #89, 2026-11-15); see the audit section in [PROJECT_STATE.md](PROJECT_STATE.md).

## Priority now: DEV pilot end-to-end (owner actions first)

DEV was redeployed from `main` on 2026-11-15 (owner-approved) and a signed release APK with `partner-features=true` exists (run 43712714294, artifact `KUNDE-dev-release`). Remaining order: (1) owner provisions one synthetic admin (SQL in the ADR-018 section below); (3) install the APK and walk Consumer login → Partner application → Admin approval → Offering → Publish → Consumer catalog (needs a PUBLISHED category, owner decision under ADR-014). Acceptance: each step recorded as VERIFIED with run/request evidence; until then the pilot is not ready. Check: after login a user without partner access gets 403 on `/api/v1/partner/categories`; after a partner application and a token refresh it returns the category list.
Consent API (PR #23), Flutter consent UI (PR #24), and Flutter saved addresses
(PR #25) are already merged. Do **not** rebuild them or close their canonical
tasks without remaining product/privacy/UX acceptance evidence.

## Latest merged verification

- PR #28 (merged `5de3184`) added native refresh-outage, replay, access-expiry and
  token-secrecy checks to the existing harness; hosted run 43270980722 passed
  (17 checks, sanitized artifact). CodeRabbit did not review; merge was owner-approved.

## Also merged since #41

#43 (TASK-010 default-deny serviceability UI), #45 (backlog CI validation), #46 (TASK-008 consent
presentation per reader language; fallback order is kk → ru → en by owner decision 2026-11-13).

## DEV phone sign-in follow-ups (owner)

Phone-OTP authentication is implemented and **was found live on DEV on 2026-11-15** (login with a synthetic number verified; the owner's apply with `replace_render=true` evidently ran, new host `kunde-backend-ty81`). The steps below are kept as the setup record (see [phone-otp-auth](docs/identity/phone-otp-auth.md#dev-setup)); originally it was not live until the owner (1) adds GitHub secret `AUTH_PHONE_SECRET` (32+ random chars) and variables `AUTH_PHONE_ENABLED=true`, `AUTH_DEV_OTP_ENABLED=true`, (2) reviews the Terraform DEV plan and explicitly approves an apply with `replace_render=true`, (3) re-runs *Android Release APK (DEV)* and installs it; sign in with `+7 700 000 00 01` / `123456`. Then report phone-check results. Also: keep the keystore backup; decide the final applicationId before any store release (affects `scripts/ci/consumer_native_e2e.py`). Production gates for own auth are listed in the doc (independent security review, OTP vendor D-11, privacy/residency, key management, distributed rate limits).

## Infrastructure DEV follow-ups (DEV is live; owner actions)

DEV Render + Neon is deployed and verified (see [PROJECT_STATE.md](PROJECT_STATE.md), [docs/infrastructure/terraform-dev-render-neon.md](docs/infrastructure/terraform-dev-render-neon.md)). Open: (1) add **Required reviewers** to the GitHub Environment `dev`; (2) watch Render free hours (shared with other services) and Neon CU-hours; (3) any change to the Render service needs the workflow with `replace_render=true` and a separate explicit apply permission; (4) production hosting/residency remains TASK-051 / D-08 — DEV must not hold real personal data.

## ADR-018 (D-14) is implemented for DEV — owner steps to run the first partner pilot

All five plan steps are merged (admin grants and scopes, partner application/profile, offerings, admin approval, Flutter section behind `PARTNER_FEATURES_ENABLED`). D-03/D-04 stay approved only for the DEV pilot (pay on receipt, KZT, 0% commission). To try it end to end on DEV with synthetic data:

1. Phone-auth must be live on DEV (see "DEV phone sign-in follow-ups" above: `AUTH_PHONE_SECRET`, Terraform apply with `replace_render=true`).
2. Provision one synthetic admin (owner, out of band; no endpoint creates it): after that user has logged in once, run on the DEV database `INSERT INTO identity.admin_grants (user_id, permission, reason) SELECT user_id, 'PARTNER_VERIFICATION', 'DEV pilot admin' FROM identity.phone_identities WHERE phone_e164 = '<synthetic number>'`. The admin then calls `/api/v1/admin/partners` (queue, detail, decision) with a refreshed token; there is no admin screen in the app.
3. Run *Android Release APK (DEV)* with input `partner-features=true`, install it, apply as a partner (Profile → For partners), approve it through the admin API, then add and publish an offering; a published offering needs a PUBLISHED category (the `food-ordering` category is still an unpublished DRAFT by ADR-014, so nothing is public until the owner publishes a category).
4. Gaps: no admin UI, no device/TalkBack run of the partner screens, no staff-management endpoints (grant/revoke roles exist only in the service), production admin needs step-up/dual control.

## Owner decisions needed (blocking further roadmap work)

- D-02, D-05, D-06, D-07 are approved. **Next most important: D-03/D-04** (payments, commission, settlement); they gate TASK-025/026/027/028 and any charge or refund.
- Partner persistence (TASK-015, V8) is in. Still missing before orders can be persisted: a partner reference on offerings (TASK-016), prices and quotes (TASK-022); `docs/architecture/12-data-model.md` requires partner reference plus item/quote snapshots, so persist `OrderLifecycle` (TASK-021) only after those exist.
- TASK-016 link (V10) and public partner detail are merged (#81, #82). Remaining without new decisions: none that adds value — partner write APIs need D-14 (partner-app audience, admin identity); price/availability need D-03/D-04. **Owner action:** review [D-03/D-04 options](docs/product/decision-drafts/P1-decisions-D-03-D-04-payments-commission.md) (recommended: split-payment via provider or direct-to-partner, pilot without online payment, KZT, percentage commission set by the owner, no promos). Meanwhile continue TASK-006 device gaps only with real devices.
- D-01 is partially approved (Food Ordering, Almaty). Still open: exact restaurants, pilot zone, operational proof. **Next most important: D-02** (who delivers); it gates TASK-019/029 and order logistics.

- TASK-001 / D-12: name alert owners/on-call and approve SLOs (unblocks TASK-047/048 beyond the draft).
- TASK-007: approved legal policy text or link for consents.
- TASK-051 / D-08: hosting and Kazakhstan region choice (needed for real backup/restore, TASK-052/056).
- TASK-006: physical devices, iOS and TalkBack runs; session-administration contract.
- Catalog (TASK-011..014): approved contracts for price, partner link, availability (ADR-014 stays).

## Support track (TASK-037 backend merged in #57, TASK-038 Flutter entry point in PR; both in_progress)

Open: device/TalkBack acceptance, order link once transactions are enabled, staff handling (blocked on D-12/D-14), notifications (D-11).
Fixed along the way: `setState(_reload)` retry bug in ConsentPanel/SupportPanel.

## Catalog track (TASK-011..014, in_progress)

Merged: category search (#35/#36), schema V5 (#33), published offerings list and detail with
pagination (#37/#39). Open: offering search, price, partner link, serviceability/availability
rules (need approved contracts; ADR-014 keeps the catalog empty and non-orderable).
Also merged, still in_progress: TASK-041 event catalog (#40), TASK-050 money formatting (#41).

## Next controlled implementation

1. Read `AGENTS.md`, `PROJECT_STATE.md`, `docs/identity/consumer-validation/README.md`,
   `scripts/ci/consumer_native_e2e.py` and the canonical backlog.
2. Remaining TASK-006 gaps (all currently NOT_EXECUTED, never successful by default):
   iOS, TalkBack/large text, full RU/KK profile journeys, physical devices and account
   session administration (existing API returns 503). Native checks need real devices/OS.
3. Keep PKCE S256, issuer/audience/time validation, strict `invalid_grant` handling,
   token redaction, account binding and negative assertions; do not label unit/protocol
   checks as native E2E.

## Parallel remaining acceptance gates

- ADA-73 / TASK-007: legal approval, policy text and retention/withdrawal
  effects before real consent can be enabled.
- ADA-74 / TASK-008: policy disclosure UX and device accessibility.
- ADA-76 / TASK-010: map-based address selection, real serviceability/out-of-zone
  behavior and device acceptance.
- GHSA-r937 remains open; no security exception, suppression or production
  authorization is implied by green CI.

Create focused branches/PRs; merge only after required CI and review.
Use canonical TASK IDs and synchronize Linear and this state file from evidence.
