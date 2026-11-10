# Known Limitations

- Existing architecture ADRs are Proposed, not accepted. This foundation follows the recommended stack but cannot establish organization approval.
- No MVP category/cohort/zone is approved; catalog and search return empty. No order, booking, payment, refund or partner/provider/admin workflow exists.
- OIDC resource-server support is scaffolded: configured issuer plus required `OIDC_AUDIENCE`; Nimbus signature and default issuer/time validation plus an explicit audience validator. Unit tests cover audience acceptance/rejection and missing-audience fail-fast. No approved issuer, live discovery/JWK fetch, signed tokens, registration, login, issuance, refresh, logout, role mapping or tenant/resource authorization has been verified.
- AI, OTP, payments, maps, messaging, analytics and crash reporting are disconnected. No credentials were supplied; no fake integration is presented.
- Backend build, tests, context, PostgreSQL/Flyway, HTTP health/readiness, fail-closed behavior and OpenAPI access passed locally on 2026-11-10 using official portable Maven 3.9.9 and isolated PostgreSQL 16.15 (final verify: 14 tests, 0 failures/errors/skips). Remote GitHub Actions was not run; no repository remote is configured in this workspace. Dependency vulnerability scanning was not run because no scanner is installed. Live issuer/JWK/signature verification remains open. Flutter 3.47.0 analysis, four tests and Android debug build passed; iOS build is configured in CI but was not run on Windows.
- OpenAPI is a checked-in OpenAPI 3.1.0 YAML contract served at `/api/v1/openapi.yaml`; it is not generated from controller annotations and has no automated schema-conformance check yet.
- Production CORS origins default to none. TLS, managed secrets, cloud region, residency, backups, monitoring/alerts, SLO/RPO/RTO and incident staffing remain unconfigured.
- RU/KK/EN localization scaffolding does not resolve D-15 official languages or legal translation workflow.
- No production-signed Android/iOS release artifacts, secure token storage or store workflow exists because there is no authentication flow and publisher identity is not approved.
- Generated Android/iOS application identifiers remain Flutter template identifiers and must be replaced with the organization's approved publisher ID before store distribution.
