# TASK-003 / ADA-69 — Repository build and review gates

Review date: 2026-11-12. Canonical scope: EP-001 / FEAT-002 / TASK-003 in `docs/roadmap/backlog/tasks.yaml`. Status remains **partially_verified**; this change does not assert production readiness.

## Actual baseline and evidence

- Backend CI (`.github/workflows/backend.yml`): PostgreSQL 16 service, Java 21, `mvn clean verify`, packaged JAR inspection and HTTP/fail-closed smoke. PR #7 records PASS with 40 tests: https://github.com/ADatkashov/kunde/actions/runs/43080508430. New PR results must be reviewed independently.
- Flutter CI (`.github/workflows/flutter.yml`): pinned Flutter 3.47.0, lockfile resolution, fatal analyzer, format gate and machine-readable tests. PR #7 records PASS with 33 tests: https://github.com/ADatkashov/kunde/actions/runs/43080508368.
- Configuration CI: PR #7 records PASS, including native prerequisite regression tests: https://github.com/ADatkashov/kunde/actions/runs/43080510982.
- Android APK: PR #5 recorded PASS for build/signature/native dependency audit: https://github.com/ADatkashov/kunde/actions/runs/43076949420. PR #7 Android result was pending in the last recorded evidence; do not treat it as confirmed PASS.
- Security CI: PR #7 reports dependency, container and Gitleaks secret scans PASS; independent Flutter SDK tooling audit FAIL on two MODERATE matches of GHSA-r937-wjx7-w2jp in upstream Kotlin Gradle Plugin tooling: https://github.com/ADatkashov/kunde/actions/runs/43080508373. No advisory suppression, scanner bypass or risk acceptance.
- Manual Android Consumer native E2E: PR #7 prerequisite run fails because native scenario scripts are missing, uploads NOT_EXECUTED evidence and does not run emulator: https://github.com/ADatkashov/kunde/actions/runs/43080577336. The correction remains in open PR #7: https://github.com/ADatkashov/kunde/pull/7.

## ADA-69 change

Previously, Security CI had a path filter on push and pull_request. Changes outside the filter could avoid receiving fresh security results, so the scan was not a dependable repository-wide review gate. Remove those filters, retaining the full existing scanner jobs, exit-code handling, least-privilege permissions and pinned tools. All PRs and main pushes now trigger Security CI; findings continue to fail honestly.

This PR does not alter application source, Flyway V2, Consumer Identity/Profile, Flutter Authentication or existing tests.

## Remaining review and owner actions

1. Inspect this PR's current-head GitHub Actions checks for backend, PostgreSQL/Flyway, Flutter, Android APK, configuration, and all Security CI jobs. A workflow trigger is not evidence of a successful run; record actual conclusions.
2. Keep SDK GHSA-r937-wjx7-w2jp unresolved until a supported upstream fix is validated on the effective graph. Do not disable or mark its audit successful.
3. Review and integrate PR #7 separately after its checks and security blockers are resolved; native browser/device E2E remains NOT_EXECUTED.
4. Verify branch protection/rulesets in GitHub Settings → Rules → Rulesets (and Settings → Branches where applicable). Require a PR before merging, prevent bypass, require up-to-date checks, and select exact successful job context names from a completed run: `Backend CI / backend`, `Flutter CI / flutter`, the configuration and Android jobs, and all four Security CI jobs (`dependencies`, `secrets`, `containers`, `sdk-tooling`). Confirm exact names in GitHub UI before saving; do not require the manual native E2E workflow as an always-triggered PR check. If settings cannot be read, do not claim protection is enabled.
5. No merge while critical failures remain. A currently red SDK security job is a blocker to a completely green protected merge, not grounds for weakening security.

Canonical backlog TASK-003 remains partially_verified until branch rules and current-head hosted checks are confirmed.
