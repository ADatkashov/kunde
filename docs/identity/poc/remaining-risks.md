# Remaining identity POC risks — recovery 3.0

The Keycloak primary Android-to-protected-API path now passes. The POC remains partial and does not authorize production provider selection.

1. Configure ZITADEL project, Native application, role/audience scopes and synthetic user; complete the equivalent Android PKCE → API flow.
2. Complete a second Keycloak login after logout and verify refresh-token invalid/replay/reuse behavior, server-side revocation, session expiry and concurrent sessions.
3. Test whether an already issued self-contained Keycloak access JWT remains accepted after logout and until its expiry. Local deletion and browser session logout are not JWT revocation.
4. Run live provider negative-token HTTP tests: tampered signature, wrong issuer/audience, expired/not-yet-valid JWT and missing permission. Existing negative cases use deterministic test keys/issuer only.
5. Exercise Android invalid callback/state, cancellation, network failure and expired refresh token. Successful PKCE establishes positive path only.
6. Verify provider key rotation against a live token and cache behavior; only fixture JWKS cache/unknown-kid retrieval has been tested.
7. Repeat TLS/bootstrap and full Maven verification only when implementation changes warrant it; previous Java 21/Boot 3.5.7 `mvn verify` passed 21 tests. Local TLS script should be run with PowerShell 7 (`pwsh`) due WinPS 5.1 API incompatibility.
8. Production legal/data-residency, pricing/support, operational ownership, backup/restore, monitoring, HA, upgrade/recovery, migration and threat model remain open. Resource observations are local idle/startup snapshots, not load testing.

Keep strict issuer, audience, signature, time and scope checks enabled. ADR-015 stays PROPOSED. TASK-005 awaits explicit provider acceptance; TASK-006 remains not complete.
