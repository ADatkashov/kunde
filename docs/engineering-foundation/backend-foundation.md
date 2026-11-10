# Backend Foundation

The backend remains one Spring Boot deployable. Controllers are transport adapters; platform errors return `ApiError` with timestamp, status, stable code, safe message, path and correlation ID. Validation does not echo rejected values. Unexpected failures are logged with correlation ID only and return a generic message. Inbound correlation IDs are limited to safe ASCII and 64 characters; otherwise the server generates a UUID.

`/api/v1/health` reports process health. Actuator exposes health only; liveness/readiness supports orchestration and readiness includes PostgreSQL health. Shutdown is graceful. JDBC pool size and port are configurable. Flyway migrations execute at startup. The checked-in OpenAPI 3.1.0 contract is served as `application/yaml` at `/api/v1/openapi.yaml`.

OIDC JWT resource-server validation is optional through `OIDC_ISSUER_URI` and `OIDC_AUDIENCE`. Nimbus validates signatures using issuer discovery/JWKs; default issuer/time validation and an explicit audience validator are composed. Missing audience with a configured issuer fails startup. Without an issuer, only health, capability, OpenAPI and empty read-only catalog/search routes are allowed. Audience and fail-closed behavior have local tests, but no real issuer/JWK endpoint or signed token was available; this is not production-verified authentication or complete authorization.

Local verification on 2026-11-10: official Maven 3.9.9 with Java 21 compiled and packaged the app; 14 tests passed against isolated PostgreSQL 16.15; live HTTP health/readiness/liveness, correlation, validation error, deny-by-default and OpenAPI checks passed. Full evidence and exact invocation are in `implementation-status.md`.

No queue/outbox, trace exporter, metrics registry, logging vendor, cache or cloud runtime is selected. Production SLOs remain subject to D-12.
