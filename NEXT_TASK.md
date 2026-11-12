# Next task — TASK-006 / ADA-72 remaining device/accessibility/session-admin verification

Last main merge: `5de31848538267105e23edddc17303dc75140887` (PR #28, 2026-11-12).
Consent API (PR #23), Flutter consent UI (PR #24), and Flutter saved addresses
(PR #25) are already merged. Do **not** rebuild them or close their canonical
tasks without remaining product/privacy/UX acceptance evidence.

## Latest merged verification

- PR #28 (merged `5de3184`) added native refresh-outage, replay, access-expiry and
  token-secrecy checks to the existing harness; hosted run 43270980722 passed
  (17 checks, sanitized artifact). CodeRabbit did not review; merge was owner-approved.

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
