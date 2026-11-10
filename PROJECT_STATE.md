# KUNDE project state

Last reviewed: 2026-11-10. See [`AGENTS.md`](AGENTS.md) for mandatory continuation rules and [`NEXT_TASK.md`](NEXT_TASK.md) for the next action.

## Product and architecture

KUNDE is at the Development Foundation stage, not a marketplace MVP. The repository contains a Java 21 / Spring Boot 3.5.7 modular-monolith API, PostgreSQL/Flyway foundation, and Flutter Consumer shell with localization scaffolding. API health/capabilities and currently empty categories/search are implemented. No production catalog, order, payment, AI, phone OTP, registration, or production identity lifecycle is enabled.

The API's OIDC resource-server boundary validates configured JWTs and fails closed for protected routes when no issuer is configured. Identity POC-only HTTP issuer allowance and `/api/v1/poc/whoami` are restricted to the explicit `identity-poc` profile. Local provider POCs use separate Compose projects and loopback ports.

## Implemented and checked

- Foundation API, PostgreSQL/Flyway, health/readiness, correlation/error handling and OpenAPI have local verification documented in [`docs/engineering-foundation/implementation-status.md`](docs/engineering-foundation/implementation-status.md).
- Flutter foundation shell is implemented; the identity POC screen uses AppAuth system-browser PKCE and secure storage, behind an opt-in build define.
- Keycloak 26.8.2 positive Android → Flutter → real access JWT → Spring protected API flow completed with a synthetic user. API returned HTTP 200 after JWT signature, issuer, `kunde-api` audience, expiry and `kunde.poc` checks. Refresh and provider logout/login-form evidence are recorded. See [`docs/identity/poc/end-to-end-evidence.md`](docs/identity/poc/end-to-end-evidence.md).
- ZITADEL 4.19.5 health/discovery passed; its project/client/test-user flow is not configured. No equivalent mobile/API flow has been demonstrated.
- Previously completed Java 21 / Maven 3.9.9 / Spring Boot 3.5.7 `mvn verify`: 21 tests passed, 0 failures/errors/skips, as recorded in identity POC evidence. Spring fixture tests are not live provider negative-token tests. Flutter analyze and four tests passed in an earlier run; not rerun in the last identity recovery.
- Secure Maven TLS bootstrap uses Windows-trusted public certificate roots, with Java TLS/hostname verification enabled. The local bootstrap is documented in [`docs/identity/poc/maven-tls.md`](docs/identity/poc/maven-tls.md); use PowerShell 7 (`pwsh`).

## Open work and blockers

- Complete equivalent ZITADEL Native OIDC app/project/user setup and Android PKCE → protected API verification.
- Complete provider-backed negative JWT and token/session lifecycle tests for Keycloak; test access JWT behavior after logout, invalid refresh/replay/revocation and expiry.
- Verify Android invalid callback/state, cancellation, network failure and full second login after logout.
- Kazakhstan privacy/data-residency, commercial terms, operations, backup/restore, HA, upgrade, monitoring and production threat review remain open.
- No production IdP is approved. POC result is partial overall.

## Decisions and status

- [ADR-013](docs/architecture/adr/ADR-013-foundation-security-boundary.md): accepted reversible fail-closed authentication boundary; no vendor approval.
- [ADR-015](docs/architecture/adr/ADR-015-proposed-identity-provider.md): PROPOSED. Keycloak is a POC front-runner only; comparison is incomplete.
- [EP-002 design gates](docs/roadmap/25-identity-ep002-design.md): owner, legal/privacy and operations gates remain. TASK-005 stays blocked pending provider/fallback decision approval; TASK-006 remains not started. The canonical backlog is [`tasks.yaml`](docs/roadmap/backlog/tasks.yaml).
- ADR-001–012 include recommendations/proposals and accepted decisions; consult each status before treating it as binding.

## Git and verification limits

At this review, the workspace contained no `.git` directory. `git status` and `git log` failed with “not a git repository”; branch, uncommitted-change state, remotes and commit history are unknown. Available decision history is documented in ADRs and roadmap files. Do not describe the workspace as clean or infer commit state.

Do not count a built APK as mobile authentication proof, fixture JWT tests as provider verification, a discovery response as a completed login, logout token deletion as JWT revocation, or POC evidence as production readiness.
