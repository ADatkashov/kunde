# Next task — TASK-006 remaining native session failure-path verification

PR #17 merged as afdab129 on 2026-11-12. Hosted Android E2E run
43219354337 completed successfully (prerequisites and emulator); its sanitized
artifact records the expanded eleven-check registration/login/profile suite.
Do not repeat native registration as an unverified next task.

Next controlled work: test refresh replay rejection, provider outage/recovery,
and session expiry using the isolated synthetic Android35/Chrome/AppAuth fixture.
Keep PKCE, fail-closed JWT issuer/audience/time validation and token redaction.
Use deterministic negative tests and retain evidence from executed native runs;
do not mistake fixture protocol mocks for native proof.

Parallel independent roadmap lanes (separate branches):
- ADA-73 / TASK-007: implement the consent contract before TASK-008 completion.
- ADA-75 / TASK-009: address/serviceability model; no real addresses or
  unapproved service zone/provider assumptions.
- ADA-119 / TASK-053: CI speed/quality, PR #18 in review.

TASK-006 remains in_progress: refresh replay, provider outage/expiry, iOS,
TalkBack, large text, full RU/KK profile journeys, physical devices and session
administration remain open. TASK-045 partially_verified; TASK-046 in_progress.
GHSA-r937 is unresolved. Production identity/OTP, privacy/residency and provider
operations are not approved. Read PROJECT_STATE.md, AGENTS.md, the canonical
backlog and docs/identity/consumer-validation/README.md before implementation.
