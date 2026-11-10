# Project Structure

```text
backend/src/main/java/kz/kunde/
  config/        security and web configuration
  platform/      health, capabilities, correlation, API errors
  catalog/       empty-result foundation contract
backend/src/main/resources/
  db/migration/  Flyway-owned schema setup
  openapi/       versioned API contract
mobile/lib/core/             localization and app primitives
mobile/lib/features/home/    foundation status query and screen
mobile/lib/shared/theme/     KUNDE theme
mobile/test/                 API and widget tests
docs/engineering-foundation/ implementation record and runbooks
docs/architecture/adr/       architecture decisions
.github/workflows/ci.yml     backend/mobile checks
compose.yaml                 local PostgreSQL and backend
```

Backend packages stay small; split domain modules as behavior is implemented rather than creating empty framework layers. Flutter is feature-first and keeps HTTP effects in its data client. OpenAPI is the compatibility reference; generated cross-language DTOs are deferred until justified.
