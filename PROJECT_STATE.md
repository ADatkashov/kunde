# KUNDE project state

Reviewed 2026-11-11. Follow AGENTS.md; code and current CI are authoritative.

- Java 21 / Spring Boot 4.0.9, PostgreSQL/Flyway V1–V2 and Flutter 3.47.0.
- ADR-015 is ACCEPTED for synthetic implementation: Keycloak primary, ZITADEL
  fallback. Production readiness, privacy, residency, operations and OTP remain gated.
- PRs #1–#3 added hosted CI, Consumer Identity/Profile and tests. Main at 22c1ae8
  had Backend/Flutter CI failures; PR #5 fixes Method Security 500s and formatting.
- Consumer /me provisions an immutable UUID from verified issuer/subject, enforces
  restricted status, scopes/client/token type and profile version. Sessions API
  explicitly returns 503 pending implementation.
- Flutter has real AppAuth browser authentication, secure token vault, serialized
  refresh/logout, splash/restore, RU/KK/EN welcome/home/profile editing and errors.
  Enable only with explicit development configuration; no production mock login.
- Current local verification: 39 backend tests with PostgreSQL and 29 Flutter tests;
  formatter/analyzer and packaged smoke passed. Real Keycloak protocol registration,
  PKCE, profile, refresh/replay, logout and subsequent login passed with synthetic
  data. This is not native browser/device E2E. See the reproducible
  [verification package](docs/identity/consumer-validation/README.md).
- Remote workflow results and merge status are recorded in PR #5. Earlier CI and
  POC evidence remain historical; they do not establish production readiness.
