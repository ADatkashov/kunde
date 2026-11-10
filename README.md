# KUNDE Super App

KUNDE is being built as a modular platform. This repository currently contains the Foundation 1.0 increment: a Spring Boot API boundary and Flutter Consumer App shell. It is **not yet a marketplace MVP**; no category, authentication provider, payment, partner cohort, AI provider or production environment is approved/configured.

## Project areas

- `backend/` — Java 21, Spring Boot modular monolith, PostgreSQL/Flyway foundation.
- `mobile/` — Flutter consumer foundation and RU/KK/EN localization scaffolding.
- `docs/` — Product, architecture, design, business, delivery roadmap and engineering foundation records.
- `compose.yaml` — local-only PostgreSQL and backend container setup.

## Start locally

See [`docs/engineering-foundation/local-development.md`](docs/engineering-foundation/local-development.md). In brief: create a local ignored `.env` with unique `DB_USERNAME`/`DB_PASSWORD`, run `docker compose up --build`, then run Flutter using the emulator API URL. Do not use local credentials outside development.

## Foundation endpoints

- `GET /api/v1/health` — process check.
- `GET /api/v1/capabilities` — enabled foundation capabilities.
- `GET /api/v1/categories` and `/api/v1/search` — currently empty until an approved catalog exists.
- `GET /actuator/health/readiness` — includes the database dependency.

Authentication only accepts JWTs from an explicitly configured OIDC issuer; no issuer means protected routes fail closed. There are no token issuance, OTP, real payment, AI or order flows. See [`docs/engineering-foundation/implementation-status.md`](docs/engineering-foundation/implementation-status.md) and [`docs/roadmap/README.md`](docs/roadmap/README.md).
