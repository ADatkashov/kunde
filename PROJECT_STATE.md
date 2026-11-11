# KUNDE project state

Reviewed 2026-11-11 after owner-authorized [PR4 merge](https://github.com/ADatkashov/kunde/pull/4), commit36ea51be25c88c1ce3b4f60e5954617cd3ab701e. The merged tree exactly matches the verified combined branch2619faf. All main22c1ae8 user-published identity/auth changes and history were preserved.

Stack: Java21, official Spring Boot4.0.9 BOM / Framework7.0.10 / Security7.0.8; PostgreSQL/JDBC/FlywayV1+V2. Flutter3.47.0, projectKGP2.4.20/AGP9.1.1/Gradle9.3.1. Digest-pinned maintained Temurin21 UBI10 images and checksum-verified Apache Maven3.10.0.

Published Consumer foundations: canonical UUID, unique verified issuer/subject binding, concurrent provisioning/account audit, account-state and optimistic profile concurrency checks, Consumer scope/client/token-type policy and Flutter secure-storage/serialized refresh repository. Feature remains opt-in; session administration is explicitly unavailable. EP-001 and historical Keycloak/ZITADEL POC/readiness evidence preserved.

Combined-source hosted verification:
- Backend43072128234:36 tests,0 failures/errors/skips; executable JAR and HTTP smoke pass, FlywayV2 and concurrent provisioning covered.
- Flutter43072128134:10 tests pass, analyze clean, formatter11 files/0 changes. New protected-profile test verifies rotated Bearer header.
- Android43072128132: actual dependency graph, debugAPK/signature and nativeOSV0/exit0 pass.
- Effective containers43072128200: both image builds/OS scans and runtime HTTP smoke pass.
- Security43072128227: Maven/Pub/build-rootOSV0, baseOS scans0 and Gitleaks pass; SDK audit fails honestly on2 MODERATE matches of1 GHSA-r937-wjx7-w2jp in upstream Kotlin tooling.
- Configuration43072128135 passes. These are actual pre-merge combined-tree checks; automatic main reruns are separate evidence.

Integration fixed method-authorization denial returning500 rather than403. Dart formatting preserves main's auth logic; a diagnostic-log mask copied into the working branch was corrected and covered by a Bearer-header regression before merge. No raw credentials or tokens published.

TASK-003 partially_verified; TASK-006/TASK-046 in_progress. Consumer native browser E2E not executed; SDK/native binary and Maven-distribution coverage gaps plus API abuse controls remain open. Provider decision records still need reconciliation with explicit owner approval in a separately scoped identity change. No production readiness, deployment, paid runner, force push or risk acceptance.

[Current ledger](docs/security/ci-vulnerability-ledger.md) · [Security runbook](docs/security/security-runbook.md) · [TASK-046](docs/security/TASK-046.md).
