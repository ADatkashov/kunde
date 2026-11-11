# Next task — review delivery and close remaining TASK-046 gates

Use GitHub branch ci/github-hosted-migration-20261111 and [current ledger](docs/security/ci-vulnerability-ledger.md). Owner explicitly authorized integration with main22c1ae8 and merge via PR4. Verify combined-source backend, Flutter, APK and security evidence before merging; never rewrite history.

Highest-priority remaining TASK-046 work: evaluate a supported upstream Flutter SDK/tooling release that eliminates GHSA-r937-wjx7-w2jp (currently SDK KGP2.0.0/2.2.21; project2.4.20 clean). Do not patch SDK internals or suppress findings. Close Maven-distribution/runtime/native SDK binary coverage gaps and implement separately scoped, documented API abuse/rate/size controls absent from published code. Current observed CRITICAL/HIGH are eliminated; incomplete coverage is not zero risk.

Reproduce with hosted Backend CI, Flutter CI, Android APK CI, Security CI and Container build and security verification. Backend29 tests/JAR/HTTP pass, APK/signature/native audit0, Maven/Pub/root0, both base/effectiveOS0; SDK audit remains exit1 with2 MODERATE matches of1 advisory. Preserve exact reports/run URLs in the ledger.

TASK-006 remains in_progress: main22c1ae8 has published canonical KUNDE UUID/profile/V2 and Flutter auth foundations. Validate these combined changes, then execute the real Consumer Android Keycloak/PKCE/JWT/profile/restart/refresh/logout/relogin scenario; native E2E remains unverified. Reconcile ADR-015 with explicit owner approval before the separately scoped implementation. No production readiness.
