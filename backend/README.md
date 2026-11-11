# KUNDE API

Spring Boot 4.0.9 / Java 21 modular-monolith foundation. Current routes and access are documented in `src/main/resources/openapi/kunde-api-v1.yaml`.

## Local run

Requires Java 21, Maven 3.9+ and PostgreSQL 16. Set `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`; then run `mvn spring-boot:run`. Flyway applies a schema-only migration. For PostgreSQL and the backend container, use root-level `docker compose up --build` after creating the ignored root `.env` as described in `docs/engineering-foundation/local-development.md`.

## Security behavior

With no `OIDC_ISSUER_URI`, only health, capabilities and empty read-only catalog/search are available; protected routes fail closed. Configuring an issuer enables JWT verification only and does not provide registration, login/token issuance, role mapping or a complete user authorization policy. Do not configure an unapproved issuer.

## Checks

Run `mvn verify`. Local database is required for full application startup; unit tests do not need vendor credentials.

## Consumer Identity and Profile

Enable `CONSUMER_IDENTITY_ENABLED=true` with an approved development issuer and
`OIDC_AUDIENCE=kunde-api`. `/api/v1/me` provisions/loads the authenticated user;
PATCH requires displayName, preferredLanguage (ru/kk/en) and current version.
Signed access tokens require issuer, audience, exp/iat/sub; consumer endpoints
add `azp=kunde-consumer`, `typ=Bearer` and `kunde.consumer` scope. Spring uses
60-second clock tolerance. API returns 401 for invalid authentication, 403 for
authorization/account restrictions, and 409 for a stale profile version.
Flyway V2 owns identity bindings, profile and account event tables. Session
administration remains 503. See
[verification and development setup](../docs/identity/consumer-validation/README.md).
