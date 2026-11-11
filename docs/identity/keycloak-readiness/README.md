# Keycloak security hardening and readiness 1.0

Local Keycloak 26.8.2, Spring Boot 3.5.7 and synthetic accounts. The test runner creates a separate realm in the existing loopback POC. See the [provider comparison](../poc/final-provider-decision-report.md) for the retained Android and ZITADEL evidence.

The 2026-11-10 live run in `kunde-security-c7a20f63` exited 0. The packaged API accepted the new signing key during overlap, and the provider stopped publishing the old key after expiry and retirement. Spring accepted previous access JWTs for about 60 seconds past `exp` under the current timestamp tolerance. The isolated backend build passed 24 tests and repackaged the JAR used in this run.

| Area | Evidence or decision |
|---|---|
| Access JWT lifetime after logout or revocation | [Access token revocation](access-token-revocation.md) |
| Rotation, reuse, expiration and concurrent refresh | [Refresh token security](refresh-token-security.md) |
| Active and passive signing keys and Spring JWKS | [Signing key rotation](signing-key-rotation.md) |
| Proposed consumer token and session settings | [Token lifecycle policy](token-lifecycle-policy.md) |
| Role, scope and JWT rejection cases | [Authorization security](authorization-security.md) |
| Backend regressions and verified artifact | [Spring Security verification](spring-security-verification.md) |
| Release gates and ownership | [Production readiness](production-readiness.md), [operational requirements](operational-requirements.md), [remaining risks](remaining-risks.md) |
| Decision and sequencing | [Implementation handoff](implementation-handoff.md) |

## Reproduce

Use Windows PowerShell 7, Java 21, Maven 3.9+, Node.js 22+ and a local Chromium browser (Edge by default, or set `KUNDE_TEST_BROWSER` to an installed executable). Start the existing local Keycloak and backend PostgreSQL stacks using the [POC guide](../poc/README.md). The runner reads the bootstrap administrator credentials from the ignored local Keycloak env file. The bootstrap admin call uses the built-in local admin client. Consumer and partner clients use public Authorization Code + PKCE S256, with a generated loopback redirect and disposable browser profile.

1. From the repository root run `node docs/identity/keycloak-readiness/verify-keycloak.mjs`. It prints the fresh realm issuer and waits for the API.
2. Set `SPRING_PROFILES_ACTIVE=identity-poc`, `POC_ALLOW_HTTP_ISSUER=true`, `OIDC_ISSUER_URI` to the printed issuer, `OIDC_AUDIENCE=kunde-api`, `SERVER_ADDRESS=127.0.0.1` and `SERVER_PORT=18085` in the API process. Clear any prior `POC_ZITADEL_ORGANIZATION_ID`. Use the isolated POC database as in the [Maven guide](../poc/maven-tls.md). Run the verified Boot JAR with `java -jar`.
3. Wait through the expiry and rotation overlap. The runner prints statuses, timing and public key IDs. It creates a fresh realm on each run and removes only the original signing component of that realm after the overlap. Each realm remains local for inspection.

Set `KUNDE_TEST_JAR` to the full path of a verified Boot JAR to have the runner start and stop its own API on loopback port 18086. This mode reads the ignored POC database settings and avoids sharing a running service's build directory.

The runner uses the stock development Compose setup and does not replay Android UI. Prior Android results remain linked separately. Synthetic credentials are generated in memory. Browser state is under ignored `../poc/.local/`. Raw tokens, callback codes and credentials are excluded from the evidence.

Two initial full realm imports timed out with shorter client deadlines. A minimal admin import returned HTTP 201. The successful full import used a longer deadline scoped to realm creation. An initial Edge DevTools command also timed out. The live run used the adjusted browser deadline and the isolated packaged API.
