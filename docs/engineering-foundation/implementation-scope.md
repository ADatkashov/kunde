# Implementation Scope

## Included

- Spring Boot configuration, PostgreSQL JDBC, Flyway namespace migration, health/readiness, capabilities, correlation IDs, safe exception handling, CORS, optional OIDC JWT verification and fail-closed no-provider behavior.
- Static OpenAPI contract; local Docker Compose topology; GitHub Actions backend/mobile checks.
- Flutter feature-first entry shell, API client, honest connection/availability states, retry, KUNDE theme and RU/KK/EN localization scaffolding.
- Unit/widget tests for empty catalog, capability flags/parsing, safe errors, correlation IDs and foundation UI.

## Not included

Registration/login/token issuance, OTP, user/partner/admin roles, user PII entities, production catalog, orders/bookings/payments/refunds, provider application, admin UI, AI provider/tools, analytics/crash vendors or deployment. These require unresolved decisions or are beyond EP-001.

## Reversible assumptions

Local development uses a PostgreSQL 16 container with credentials from ignored `.env`; Compose refuses to start without caller-supplied values. Database namespaces document ownership only, not populated domain tables. Public capability and health reads expose no personal information. Category/search return empty results until a persistent approved catalog exists.
