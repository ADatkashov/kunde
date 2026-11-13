# Next task — TASK-006 / ADA-72 remaining device/accessibility/session-admin verification

Last main merge: `ab001ac18ec7dd98986aa77d67fb36f3970ed693` (PR #41, 2026-11-13).
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

## Owner decisions needed (blocking further roadmap work)

- D-02, D-05, D-06, D-07 are approved. **Next most important: D-03/D-04** (payments, commission, settlement); they gate TASK-025/026/027/028 and any charge or refund.
- Partner persistence (TASK-015, V8) is in. Still missing before orders can be persisted: a partner reference on offerings (TASK-016), prices and quotes (TASK-022); `docs/architecture/12-data-model.md` requires partner reference plus item/quote snapshots, so persist `OrderLifecycle` (TASK-021) only after those exist.
- Next implementable work without new decisions: TASK-016 (offering ↔ partner link; offerings visible only when the partner is APPROVED and the category PUBLISHED). Partner/admin HTTP APIs stay blocked on a partner-app client/audience decision and a KUNDE Administrator identity (D-14).
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
