# Next task — TASK-006 native Consumer verification

After the TASK-046 verified-identity quota PR is reviewed/merged, implement the
missing isolated native-browser scenario required by android-e2e.yml. This verifies
existing Consumer behavior under ADR-015's synthetic-development approval; it does
not enable production identity/OTP. Use docs/identity/consumer-validation/README.md
and the existing POC networking guidance; do not replace PKCE with password grants.

Acceptance: real system-browser login/registration and callback, secure-vault
restore, profile load/edit, rotation/replay handling, offline/expiry recovery,
logout and credential prompt, RU/KK/EN and supported accessibility checks. Produce
sanitized evidence without token/password logs. A protocol fixture or APK build
alone is not native Consumer E2E. iOS/device/accessibility prerequisites must remain
explicit when unavailable. Preserve current API/JWT/profile/security regressions.

TASK-045 stays partially_verified and TASK-046 in_progress: trusted device identity,
canonical-account-wide quotas across IdP aliases and distributed-edge controls need
binding/operational contracts. Do not invent a trusted device from caller headers,
select unapproved hosting, or suppress SDK GHSA-r937. The local IP/body/verified
identity controls are foundation safeguards, not pilot/production readiness.
