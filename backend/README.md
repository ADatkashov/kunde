# KUNDE API

Spring Boot 3.5 / Java 21 modular-monolith foundation. Current routes and access are documented in `src/main/resources/openapi/kunde-api-v1.yaml`.

## Local run

Requires Java 21, Maven 3.9+ and PostgreSQL 16. Set `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`; then run `mvn spring-boot:run`. Flyway applies a schema-only migration. For PostgreSQL and the backend container, use root-level `docker compose up --build` after creating the ignored root `.env` as described in `docs/engineering-foundation/local-development.md`.

## Security behavior

With no `OIDC_ISSUER_URI`, only health, capabilities and empty read-only catalog/search are available; protected routes fail closed. Configuring an issuer enables JWT verification only and does not provide registration, login/token issuance, role mapping or a complete user authorization policy. Do not configure an unapproved issuer.

## Checks

Run `mvn verify`. Local database is required for full application startup; unit tests do not need vendor credentials.
