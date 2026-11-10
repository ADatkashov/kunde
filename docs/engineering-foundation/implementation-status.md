# Implementation Status

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
