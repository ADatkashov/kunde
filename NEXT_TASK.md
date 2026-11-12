# Next task — TASK-006 native registration verification

Verify the ADA-72 registration extension on its PR, then resolve any native failures.
The harness now includes cancellation, mismatched-password validation, registration
callback, canonical UUID/profile persistence and registered-user relogin. Execution
evidence is pending; do not count these as passed.

Extend the existing Android35/Chrome scenario with the Consumer's real registration
flow and callback. Source db13a26 passed six targeted login/profile/vault/offline/
logout checks in hosted run 43209945677. Reuse the disposable fixture, real AppAuth
PKCE and canonical identity/profile checks; do not replace them with protocol mocks.

Acceptance: launch Create account from Flutter, submit a fresh synthetic account
in the real provider form, return through the native PKCE callback, verify the
canonical profile and same-account relogin. Cover the provider's explicit validation
failure without logging credentials, tokens or authorization URLs. Preserve all
six existing native checks, 68 backend and 33 Flutter regression tests and the
hash-pinned Python dependency audit. See docs/identity/consumer-validation/README.md.

TASK-006 stays in_progress: native replay capture, provider outage/expiry, iOS,
TalkBack, large text, full RU/KK profile journeys, physical devices and session
administration remain open. Production identity/OTP is not approved by this work.

TASK-045 stays partially_verified and TASK-046 in_progress: trusted device identity,
canonical-account-wide quotas across IdP aliases and distributed-edge controls need
binding/operational contracts. Do not invent a trusted device from caller headers,
select unapproved hosting, or suppress SDK GHSA-r937. The local IP/body/verified
identity controls are foundation safeguards, not pilot/production readiness.
