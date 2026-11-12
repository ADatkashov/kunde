# Implementation Status

Latest branch evidence: [TASK-006 native scenario](#task-006-native-scenario--2026-11-12).
Historical snapshots below retain their original source and test scope.

**Implemented** means source/config added; **verified** requires a command actually run; **scaffolded** means a boundary exists without a real provider/flow; **blocked** means a decision/external dependency is missing; **not started** means absent.

| Area | State | Evidence / remaining |
|---|---|---|
| API foundation | Implemented and verified locally | Spring Boot 3.5.7 / Java 21; Maven `verify` passed; live health, error, correlation and OpenAPI HTTP checks passed |
| PostgreSQL/Flyway | Implemented and verified locally | Isolated PostgreSQL 16.15; Spring context connected; V1 created six schemas and history row; repeat migration executed zero migrations; readiness/liveness UP |
| OIDC authentication | Scaffolded; provider integration unverified | Issuer, signature/time validation and required audience are configured; audience/misconfiguration unit checks and no-issuer fail-closed test passed; no approved live issuer or tokens |
| Consumer Flutter | Implemented and verified | Flutter 3.47.0 / Dart 3.13.0: format check clean, analyze clean, 4 tests passed, Android debug APK built |
| Catalog and AI | Disabled | No real category data or model/provider; no demo response |
| CI | Configured and statically validated; remote workflow not executed | Workflow YAML parsed; Java 21, Maven `verify`, PostgreSQL service, Maven cache and least-privilege permissions inspected; JAR is built but not uploaded/published; workspace has no Git remote |
| Tests | Backend and mobile passed locally | Backend: 14 tests, 0 failures/errors/skips; Flutter: 4 tests passed; Android debug build and analysis previously passed |
| Production | Not started | No cloud, credentials, legal approval, operational owners or deploy target |

Backend verification record (2026-11-10): system Maven CLI/wrapper and local dependency cache were absent. Docker Hub had previously aborted Maven image authorization. Apache Maven 3.9.9 was downloaded from the official Apache archive and SHA-512 verified. Maven Central initially failed Java PKIX validation; a temporary Java truststore populated from Windows trusted roots restored normal TLS validation without disabling certificate checks. From `backend/`, final command `..\.ep001-maven-tmp\apache-maven-3.9.9\bin\mvn.cmd --batch-mode --no-transfer-progress -Dmaven.repo.local=..\.ep001-maven-tmp\m2 verify` completed **BUILD SUCCESS** with 14 tests (0 failures/errors/skips). Compose command `docker compose --project-name kunde-ep001-verify --env-file .ep001-maven-tmp/verification.env config --quiet` passed; isolated PostgreSQL 16.15 applied V1 and repeated migration was idempotent. The packaged app ran with `DB_URL=jdbc:postgresql://localhost:5432/kunde` and `PORT=18080`; live health, readiness, liveness, correlation ID, fail-closed route, validation envelope and OpenAPI 3.1 YAML checks passed. Temporary app/container/volume/network and Maven artifacts were verification-only. Workflow and OpenAPI YAML parsed with SnakeYAML; workflow structure was reviewed, but no remote run was possible because this checkout has no Git remote. No dependency vulnerability scan, production deployment or live OIDC provider/token verification is claimed.

**EP-001 backend verification: complete locally.** This does not mark the entire project epic/release approved: governance decisions, remote CI execution and live identity-provider verification remain open.
# Current main reconciliation — 2026-11-11

This section supersedes historical workstation/no-remote statements below.
Reviewed main `4595309` (merged PR #5). Hosted Backend
[43078224891](https://github.com/ADatkashov/kunde/actions/runs/43078224891), Flutter
[43078224810](https://github.com/ADatkashov/kunde/actions/runs/43078224810), Android
[43078224874](https://github.com/ADatkashov/kunde/actions/runs/43078224874) and configuration
[43078224746](https://github.com/ADatkashov/kunde/actions/runs/43078224746) succeeded.
PR #5 records 40 backend and 33 Flutter tests and separate protocol evidence.
These are remote evidence, not tests rerun in this Cloud checkout.

All 56 existing TASK IDs now have explicit implementation states in the canonical
backlog. Profile/consent and localization are partial; empty catalog/search and
schema scaffolds are partial, not completed features. Unimplemented domains remain
not_started; unresolved business/legal approvals remain blocked. TASK-005's
synthetic provider selection is accepted by ADR-015, while production gates remain
blocked. No release or epic is declared complete.

TASK-003 correction: manual native E2E now fails when any required controller or
scenario script is absent, writes NOT_EXECUTED evidence and retains the artifact.
Two executable regression tests cover each absent prerequisite and the ready case;
presence alone never claims E2E success. Security CI still fails honestly on the
upstream Flutter SDK GHSA-r937 tooling finding. TASK-003 remains partially_verified;
TASK-006 and TASK-046 remain in_progress.

# TASK-046 API quota verification — 2026-11-12

Branch increment started on main `095ce75`, then integrated main `1d367bf`; not a claim of merged source or release
readiness. `mvn --batch-mode --no-transfer-progress clean verify` in GPT Cloud,
using checksum-verified Java21 JDK/Maven and isolated PostgreSQL16.15, passed
47 tests with zero failures/errors/skips and built the executable JAR. Six new
deterministic quota tests and a real embedded-server HTTP test cover allowed and
denied requests, concurrency, spoofed headers, Retry-After and probes. See
[TASK-046](../security/TASK-046.md) for exact scope and configuration.

TASK-046 remains in_progress: the SDK GHSA-r937 finding, account/device/distributed
edge quotas, request-body limits and supply-chain coverage remain open. The packaged JAR smoke passed health200, protected-without-issuer503
and OpenAPI200 after the final CORS fix; hosted checks are recorded in the PR.

## TASK-046 body limit verification — 2026-11-12

Branch increment based on merged main 5e8c182. Cloud Java 21/PostgreSQL16.15
`mvn --batch-mode --no-transfer-progress clean verify` passed **57 tests**, zero
failures/errors/skips, and produced the executable JAR. Ten new tests cover bounded
byte reads, known/absent/understated length, UTF-8, stream/reader semantics, invalid
configuration, actual fixed-length/chunked HTTP, encoded paths, CORS and real JSON
conversion. The initial HTTP regression on main accepted excess with 200; the
implemented guard rejects it with 413 before parsing or controller effects.

`scripts/ci/smoke_backend.py` passed against the actual JAR and synthetic database:
health 200, protected-without-issuer 503, OpenAPI 200, exact body boundary 200, known
excess 413, chunked/encoded-prefix excess 413. It explicitly sets a 64-byte fixture
budget to verify environment configuration. The application default is 65536 bytes;
neither value is an approved production workload policy. OpenAPI response references
and smoke Python syntax parse. Hosted current-head evidence belongs in the PR.

TASK-046 remains in_progress: account/device/edge controls, read-timeout/concurrency
budgets, SDK GHSA-r937 and supply-chain coverage remain open. No provider, native
Consumer E2E or production-readiness claim is made. See [TASK-046](../security/TASK-046.md).

## TASK-045/046 verified-identity quota — 2026-11-12

The initial HTTP reproduction on main bb5619b returned 200 after a configured
identity budget was exhausted. Local clean verify of the new guard passes 68 tests
with no failures/errors/skips, including all existing 57 tests. The 11 new tests
cover actual signed-RSA/JWKS HTTP, rotation, forged signature rejection without
victim budget consumption, distinct identities, cross-chain budgets, peer changes,
claim shape, bounded saturation, expiry/rounding and concurrent admission.
These are local synthetic signed-token fixtures, not live IdP/native E2E proof.

Existing peer-IP semantics are preserved through shared FixedWindowQuota; the
original 6 filter regressions remain green. Packaged JAR smoke passes unchanged
health 200, protected 503 without issuer, OpenAPI 200, body-boundary 200 and fixed/
chunked 413 checks. Hosted results belong in the current PR.

TASK-045's stale build-pending note is corrected to partially_verified, with a
[technical threat/evidence matrix](authentication-and-security.md). Formal privacy,
production threat, operational ownership and supply-chain coverage reviews remain
open. TASK-046 stays in_progress for canonical-account/device/distributed-edge and
production controls; SDK GHSA-r937 is still open. No release is promoted.

## TASK-006 native scenario — 2026-11-12

Main 51374d1 includes PRs #11–#13 and the 68-test backend/33-test Flutter baseline.
PR #14 adds a disposable loopback Keycloak26.8.2/PostgreSQL/API stack, a signed
Consumer debug APK and six targeted Android/Chrome session checks. Cloud bootstrap
`clean verify` passes 68 tests. Fourteen local Python tests pass; the pinned Python
DevTools transport is now included in existing Security CI OSV scanning, with no
known findings. Independent Cloud Chromium real form submission, S256 exchange and
protected `/me`200 pass. This is not native callback/vault evidence.

Hosted Android30 runs pass welcome RU/KK/EN, then fail before credentials.
[43208441308](https://github.com/ADatkashov/kunde/actions/runs/43208441308) diagnoses
Keycloak Cookie not found with zero DOM inputs, while both device HTTP probes return
200. [43209945677](https://github.com/ADatkashov/kunde/actions/runs/43209945677),
source db13a26, passes all six targeted checks on Android35/Chrome124.0.6367.219:
welcome RU/KK/EN, system-browser login/PKCE callback/API, canonical profile edit,
two vault/rotated-refresh restores, API offline retry and provider logout followed
by credential-form relogin. The sanitized report and screenshot were inspected;
fixture cleanup succeeded. The report remains EXECUTED_PARTIAL and is retained in
[the evidence snapshot](../identity/consumer-validation/native-evidence-2026-11-12.json).
TASK-006 remains in_progress; native registration/replay/expiry/provider outage,
iOS, TalkBack, large text, full RU/KK profile journeys, physical devices and session
administration are still incomplete. SDK GHSA-r937 remains open; no production/release readiness follows.
Detailed commands, sanitized evidence and limits are in the
[Consumer verification record](../identity/consumer-validation/README.md).
