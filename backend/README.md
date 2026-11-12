# KUNDE API

Spring Boot 4.0.9 / Java 21 modular-monolith foundation. Current routes and access are documented in `src/main/resources/openapi/kunde-api-v1.yaml`.

## Local run

Requires Java 21, Maven 3.9+ and PostgreSQL 16. Set `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`; then run `mvn spring-boot:run`. Flyway applies a schema-only migration. For PostgreSQL and the backend container, use root-level `docker compose up --build` after creating the ignored root `.env` as described in `docs/engineering-foundation/local-development.md`.

## Security behavior

With no `OIDC_ISSUER_URI`, only health, capabilities and empty read-only catalog/search are available; protected routes fail closed. Configuring an issuer enables JWT verification only and does not provide registration, login/token issuance, role mapping or a complete user authorization policy. Do not configure an unapproved issuer.

## Checks

API requests have a bounded per-process peer-IP quota: by default 120 requests
per 60 seconds, with at most 4096 peer entries. Exhaustion returns 429 with
`Retry-After` and the existing JSON error envelope. Health probes are excluded.
Forwarded headers are not trusted; reverse-proxy peers share a quota. Configure
`API_RATE_LIMIT_REQUESTS`, `API_RATE_LIMIT_WINDOW_SECONDS` (1–3600), and
`API_RATE_LIMIT_MAX_CLIENTS`. See [TASK-046](../docs/security/TASK-046.md) for
deployment limits and remaining account/device/edge controls.

After bearer JWT verification, a separate budget limits each exact `(issuer,
subject)` pair to 60 API requests per 60 seconds by default, with at most 4096
identity entries per process. Configure `API_AUTH_RATE_LIMIT_REQUESTS`,
`API_AUTH_RATE_LIMIT_WINDOW_SECONDS` (1–3600), and
`API_AUTH_RATE_LIMIT_MAX_IDENTITIES`. Token rotation, peer-IP changes and caller
account/device headers cannot reset this budget. This does not merge IdP aliases
into the canonical KUNDE account or provide distributed/device quotas.

API bodies are bounded before JWT verification and controller execution. Set
`API_MAX_BODY_BYTES` (default 65536; allowed range 1–1048576). Excessive declared
or streamed bodies return 413 / `PAYLOAD_TOO_LARGE` with the existing correlated
JSON envelope. CORS and empty health probes retain their behavior. This bounds
the current synchronous JSON API; upload/form/nonblocking endpoints and ingress
upload/idle timeouts require separate review before enabling those capabilities.

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
