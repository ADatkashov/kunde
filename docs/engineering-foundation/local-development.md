# Local Development

## Backend and database with Docker

1. Install Docker Desktop and start its Linux container engine.
2. Create an ignored root `.env` with unique local-only values:

```dotenv
DB_USERNAME=kunde_local
DB_PASSWORD=replace-with-a-random-local-password
```

3. From the repository root, run `docker compose up --build`.
4. Check `http://localhost:8080/api/v1/health`, `/actuator/health/readiness` and `/api/v1/capabilities`.
5. Stop with `docker compose down`; the named volume retains local data. `docker compose down -v` discards that local database and should only be used for an intentional reset.

## Run backend outside Docker

Install Java 21, Maven 3.9+ and PostgreSQL 16. Set `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` and optional `PORT` in the current shell, then run `mvn --batch-mode --no-transfer-progress verify` from `backend/` to compile, test and package; run `mvn spring-boot:run` to start the service. Tests require the configured database, so use an isolated local/test database. Flyway applies a non-destructive namespace migration at startup. Startup fails if the database is unavailable so readiness does not misrepresent state.

To enable JWT verification, set both `OIDC_ISSUER_URI` and `OIDC_AUDIENCE` from the approved provider. Never use a placeholder. With no issuer, protected routes are denied; an issuer without an audience fails startup. No live provider has been approved or verified. Do not put production credentials or personal data in local environments.

The foundation API contract is available at `http://localhost:8080/api/v1/openapi.yaml`. Actuator exposes `/actuator/health`, `/actuator/health/readiness` and `/actuator/health/liveness`; health details remain hidden. `/actuator/info` is not exposed.

## Flutter app

Install Flutter and run `flutter pub get`, `flutter analyze --fatal-infos` and `flutter test` from `mobile/`. Run with `--dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1/` for Android emulator, or the host-reachable address for other devices. Use HTTPS for shared environments. No account, catalog, AI or order flow is enabled.
