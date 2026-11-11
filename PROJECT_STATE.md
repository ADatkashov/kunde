# KUNDE project state

Reviewed 2026-11-11 against the published GitHub branch, not recovered Cloud files.

Java21 / supported Spring Boot4.0.9 BOM resolves Framework7.0.10 and Security7.0.8. JDBC/PostgreSQL/FlywayV1 preserved. Flutter3.47.0 Consumer shell and existing Keycloak/ZITADEL POC/readiness evidence preserved. Cloud-only canonical profile/V2/abuse implementation is not present and is not recreated by TASK-046.

[Current security ledger](docs/security/ci-vulnerability-ledger.md): historical baseline437 unique advisories (12 CRITICAL/38 HIGH maximum severities); observed current Maven/Pub/build roots and project Android graph OSV0, immutable UBI10 bases and both effective container stages Trivy0. Flutter SDK tooling retains one unique MODERATE GHSA-r937-wjx7-w2jp / two KGP versions; SDK/native/runtime binary coverage remains incomplete.

Backend run43068283689:29 tests pass, executable JAR and HTTP smoke pass. Flutter run43068682084: analyze/test/format pass. Android run43043575387: APK/signature and project native OSV pass, KGP2.4.20/AGP9.1.1/Gradle9.3.1/Java21. Effective containers run43068558521: build/runtimeOS0, actual runtime health200/protected503. Security run43068682183: Maven/Pub/root and base scans/Gitleaks pass, SDK audit fails honestly on two MODERATE matches.

PR1 was externally merged at2026-11-11T15:41:52Z; existing remediation branch continues separately. No main writes, force pushes, deployment or risk acceptance by this task. External merge reverted POC isolation; restored production exclusion while retaining signed ZITADEL grant validation;29 tests verify combined source. Earlier26-test result is historical. Do not call merged PR draft.

TASK-003 partially_verified; TASK-046 and TASK-006 in_progress. Consumer canonical identity/profile and real native E2E remain open; historical provider POC is not TASK-006 acceptance. Provider policy approval was explicitly given in owner instructions; ADR-015 and old main tracking still require reconciliation in separately scoped identity work. No production readiness.

[Runbook](docs/security/security-runbook.md) · [TASK-046](docs/security/TASK-046.md) · [Boot migration ADR](docs/architecture/adr/ADR-016-supported-spring-boot-4-security-migration.md).
