# Security verification results — recovery 3.0

## Observed

- Keycloak public client completed Authorization Code + PKCE through Android AppAuth/system browser. Existing client config enables standard authorization flow, PKCE S256, exact app callback; implicit and password grants are disabled. No mobile client secret is present.
- Live Keycloak access token was accepted by Spring after actual signature/JWKS, exact issuer, audience, expiration and `kunde.poc` authorization checks. The endpoint returned HTTP 200. Flutter did not log tokens.
- Missing-subject claim was diagnosed without values and corrected by assigning Keycloak's normal subject protocol mapper in a default `basic` scope. Issuer and audience validation were never disabled.
- Refresh operation succeeded. Logout cleared local tokens and requested provider end-session; the following authorization showed the Keycloak login form, consistent with browser SSO session termination.
- Maven bootstrap retains Java TLS certificate-chain and hostname verification. No insecure SSL flags or unverified certificate imports were used.
- Existing deterministic Spring HTTP tests pass the invalid-token and JWKS-cache/rotation fixtures (21 total Maven tests previously passed). These do not establish real-provider negative-token behavior.

## Not tested / remaining security work

ZITADEL client-backed PKCE, provider-backed wrong issuer/audience/signature/time tests, tampered callback/state, nonce-specific negative case, cancel/network interruption, refresh replay/reuse policy, revoked-refresh submission, access JWT after logout, explicit provider revocation endpoint, concurrent sessions, provider key rotation, secure-storage extraction and formal penetration testing. Existing token configuration and tests must not be represented as evidence for these cases.

Never use ID tokens at the API, password grant, embedded browser or client secret. Before production: add provider-backed negative matrix, assess residual access-token revocation window and callback attack handling, threat-review device storage, abuse limits, account recovery, MFA/admin protection, legal/privacy and incident operations.
