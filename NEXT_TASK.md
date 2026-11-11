# Next task — remaining TASK-046 security gates

Main now includes owner-authorized [PR4](https://github.com/ADatkashov/kunde/pull/4), merge36ea51b. Preserve the published Consumer identity/profile/FlywayV2/auth repository and the supported Boot4/native/container remediation. Read PROJECT_STATE.md and the [security ledger](docs/security/ci-vulnerability-ledger.md).

Next independent engineering work is TASK-046 API abuse controls already documented in the backlog: bounded request sizes, validated payloads, bounded rate limiting with trusted identity/proxy boundaries,429/Retry-After and deterministic negative regression tests. Inspect current source and TASK-045 prerequisites before implementation; do not recreate published identity modules.

Separately track upstream Flutter SDK GHSA-r937-wjx7-w2jp: projectKGP2.4.20 is verified, SDKKGP2.0.0/2.2.21 remains MODERATE. Use a supported upstream fix, no SDK source patches, unsupported forced combinations or suppression. Close distribution/runtime/native binary coverage gaps with explicit evidence.

Verification baseline: combined-tree backend36/36, Flutter10/10+analyze/format, APK/signature/nativeOSV0, Maven/Pub/buildroots0, base/effectiveOS0 and container/JAR smoke pass. SDK audit exit1 is a real open finding; do not call all security CI green. Exact run URLs are recorded in PROJECT_STATE/ledger/PR4.

TASK-006 remains in_progress pending required real Consumer Android Keycloak/PKCE/JWT/profile/restart/refresh/logout/relogin E2E and remaining acceptance. Historical provider POC or APK alone does not close it. TASK-046 remains in_progress. No production readiness.
