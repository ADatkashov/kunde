# ADR-016 — Supported Spring Boot 4 security remediation

Status: ACCEPTED for the development remediation branch, 2026-11-11.
Authority: project-owner TASK-046 GitHub Security Remediation 3.0 explicitly authorizes a supported migration. Production readiness and release approval are separate.

The published baseline used Boot 3.5.7 / Framework 6.2.12 and had 72 OSV matches, including 10 CRITICAL. Prior Cloud-only results were not evidence for this repository.

Use Java 21 and the official Spring Boot 4.0.9 BOM, resolving Framework 7.0.10, Security 7.0.8, Tomcat 11.0.27, Flyway 11.14.1 and PostgreSQL JDBC 42.7.14. No individual Spring-module overrides. Replace modularized web/resource-server/test starters and use starter-flyway. Retain explicitly selected, officially supported Jackson 2 compatibility (2.21.7); Jackson 3 (3.1.7) remains managed separately. Static OpenAPI requires no springdoc migration. JDBC/Flyway V1 remains; JPA/Hibernate are not application dependencies.

Hosted evidence: backend run 43043575438 passed 26 tests; after integrating published signed ZITADEL grant verification and restoring production POC isolation, run 43068283689 passed 29 tests, packaged the executable JAR and passed HTTP smoke. Maven/Pub and build-root OSV in run 43043575403 returned zero findings / exit 0.

Risks: major-version API/serialization changes, official Jackson compatibility bridge lifecycle and evolving advisory data. Security boundaries are covered by negative JWT, scope, CORS, profile-isolation and error/logging tests; no canonical account/profile or abuse implementation is claimed. Re-run the actual dependency graph after every BOM change. No production deployment or accepted security risk.
