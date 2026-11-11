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

## Final evaluation 4.0

The focused Maven run passed **13 tests** with zero failures/errors/skips. Six exercise real Spring HTTP filters against an isolated issuer and generated JWKS. Four exercise issuer configuration and three exercise the ZITADEL grant mapping. The fixtures independently reject a bad signature, wrong issuer, wrong audience, expired or future token and missing scope. JWKS cache hits and unknown-`kid` refetch passed with generated keys.

Commands used the local Java 21/Maven cache and the isolated PostgreSQL test database. One run inherited the `identity-poc` profile and failed the default-profile expectation. Removing those launch variables produced the 13 passing results. Repackaging failed on Windows when the Boot plugin could not rename the existing JAR. The final runtime used `spring-boot:run` from the tested classes. The historical 21-test `verify` remains separate.

| Check | Keycloak live | ZITADEL live | Isolated evidence |
|---|---|---|---|
| Valid bearer | Historical HTTP 200 from Flutter, before and after refresh | HTTP 200 before and after refresh from both Flutter and the protocol probe | Signed positive fixture HTTP 200 |
| Missing bearer | HTTP 401 | HTTP 401 | HTTP 401 |
| Signature / issuer | Cross-provider ZITADEL JWT rejected HTTP 401 with Keycloak configured. This varies both issuer and signing key. | Live discovery signing key matched the authentic access JWT | Separate bad signature and issuer HTTP 401 |
| Wrong audience | Fixture only | Fixture only | HTTP 401 |
| Expired or not yet valid | Historical expired access HTTP 401; no new time manipulation | Fixture only | Both HTTP 401 |
| Insufficient authorization | Fixture only | HTTP 403 for a real JWT from the no-grant user, using the same audience and requested role scopes | HTTP 403 for missing scope; requested ZITADEL scope alone, malformed or wrong-organization/project claims grant no access |
| ID token used as bearer | Client-audience fixture only | HTTP 403 for real ID token with project audience. Access JWT had `jti`, ID token lacked it. | Mapping denies role-bearing JWTs without the access-token identifier |
| JWKS | Live positive validation previously observed | Live key ID matched; no rotation performed | Cached key and unknown-`kid` refresh passed |
| Refresh and revocation | Historical mobile refresh passed. Replay/revoke remain untested. | Refresh HTTP 200, rotation observed, invalid/replayed refresh HTTP 400, explicit refresh revocation HTTP 200, refresh after revocation HTTP 400. The already-issued access JWT still returned HTTP 200 immediately afterwards. | Provider protocol outcomes only |
| PKCE wrong verifier | Untested | Token endpoint HTTP 400 for a new authorization code with a different verifier | Real provider protocol probe |
| Logout and callback | Historical logout followed by a fresh login prompt | Android logout cleared local tokens. Selecting the remembered account required its password, then second PKCE and API HTTP 200 passed. Earlier Android cancellation observed. | Browser evidence from the real provider |

The bounded Keycloak protocol probe reached the login form but its headless HTTP client received HTTP 400 `cookie not found` at login submit. No fresh Keycloak token pair was obtained for replay and revoke. This is a probe/environment limitation. The retained Android positive evidence used Chrome and the existing realm remained intact.

Remaining security work includes real key rotation, isolated provider audience and expiry cases, callback state/nonce and network interruption, and the lifecycle of already-issued JWTs after browser logout. The [decision report](final-provider-decision-report.md) records launch gates.
