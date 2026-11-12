# Next task — TASK-006 / ADA-72 native session failure-path verification

Last main merge: `af61a2e586db2bed382677fad4aa5be869a5d99a` (2026-11-12).
Consent API (PR #23), Flutter consent UI (PR #24), and Flutter saved addresses
(PR #25) are already merged. Do **not** rebuild them or close their canonical
tasks without remaining product/privacy/UX acceptance evidence.

## Next controlled implementation

1. Read `AGENTS.md`, `PROJECT_STATE.md`,
   `docs/identity/consumer-validation/README.md`,
   `scripts/ci/consumer_native_e2e.py`, its tests and the canonical backlog.
2. Extend the **existing** synthetic Android35/Chrome/AppAuth native harness
   with deterministic refresh-token replay rejection, provider outage/recovery
   and access/session expiry evidence. Reuse the fixture and existing secure
   redaction/evidence pipeline. Do not create a new authentication architecture.
3. Keep PKCE S256, issuer/audience/time validation, strict `invalid_grant`
   handling, token redaction, account binding and negative assertions.
   Unit/protocol checks already cover some cases; do not label them native E2E.
4. Execute relevant Python/Flutter/backend checks and hosted native workflow;
   retain only sanitized evidence. If a device scenario cannot execute, mark it
   **NOT_EXECUTED**, never successful.
5. Keep iOS, TalkBack, large text, full RU/KK journeys, physical-device
   coverage and session administration explicitly open until actually verified.
   The existing session-admin API returns 503.

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
