# Next task — TASK-006 / ADA-72 remaining device/accessibility/session-admin verification

Last main merge: `ab001ac18ec7dd98986aa77d67fb36f3970ed693` (PR #41, 2026-11-13).
Consent API (PR #23), Flutter consent UI (PR #24), and Flutter saved addresses
(PR #25) are already merged. Do **not** rebuild them or close their canonical
tasks without remaining product/privacy/UX acceptance evidence.

## Latest merged verification

- PR #28 (merged `5de3184`) added native refresh-outage, replay, access-expiry and
  token-secrecy checks to the existing harness; hosted run 43270980722 passed
  (17 checks, sanitized artifact). CodeRabbit did not review; merge was owner-approved.

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
