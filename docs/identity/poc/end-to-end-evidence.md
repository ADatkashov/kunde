# End-to-end evidence — recovery 3.0

Execution date: 2026-11-10. Synthetic local account; no secret or raw token is reproduced here.

## Keycloak → Flutter → Spring Boot

| Step | Evidence | Result |
|---|---|---|
| Provider and discovery | Keycloak 26.8.2 realm `kunde-dev`; discovery issuer `http://localhost:8180/realms/kunde-dev`; JWKS retrieved | Reachable over Android `adb reverse` |
| Android app | Pixel 9 Pro AVD (Android 37.1 Google Play x86_64, `emulator-5554`); debug APK installed/launched | PASS |
| System browser | Chrome Custom Tab displayed Keycloak login form (screenshot `docs/identity/poc/.local/keycloak-login-form.png`) | PASS; not WebView |
| User authorization and callback | Synthetic user login; app status screenshot `keycloak-auth-submitted2.png` shows **Authorization Code + PKCE completed** | PASS (AppAuth Authorization Code + PKCE) |
| Provider token | Spring claim-shape diagnostic saw issuer and subject present, one audience, scope present. Values are omitted from logs/docs. | Real provider JWT reached resource server |
| Protected API | Flutter result screenshot `keycloak-api-with-sub.png` shows `HTTP 200`, `authenticated:true`, expected realm issuer, `kunde-api` audience and `kunde.poc` scope | PASS |
| Refresh | Flutter screenshot `keycloak-refresh-after-subject.png` shows refresh completed; API call after refresh returned 200 | PASS |
| Logout | Flutter status screenshot `keycloak-refresh.png`/logout UI showed local token clearing and provider logout request. Next Custom Tab screenshot `keycloak-relogin-after-logout.png` shows username/password form. | Prior browser session not silently reused; re-login was initiated, not completed in retained evidence |

Screenshots are ignored local artifacts (not committed) and contain only UI, no token panel. Exact shell/process logs may be transient; safe server diagnostic logs recorded claim names/presence only. The app did not expose authorization code or JWT in its UI.

## ZITADEL status

ZITADEL 4.19.5 Compose startup completed in 96.1 seconds. Postgres, API, Login UI and local proxy reported healthy. OIDC discovery returned issuer `http://localhost:8280`, authorization `http://localhost:8280/oauth/v2/authorize`, token `http://localhost:8280/oauth/v2/token`, JWKS `http://localhost:8280/oauth/v2/keys`, end-session `http://localhost:8280/oidc/v1/end_session`. No project/native application/user was configured and no Android request/token/API scenario was completed. It is not an authentication failure; client setup remains a blocker.

## Boundaries

The existing `mvn verify` result (21 tests passed) and six deterministic JWT/JWKS HTTP scenarios are fixture/build evidence, not live provider negative-token testing. Live Keycloak wrong-issuer/audience, invalid signature, expired/not-before, scope-denial variants were not submitted. Refresh replay, invalid refresh, revocation endpoint behavior, and whether an already issued access JWT survives logout were not verified. ZITADEL equivalence is open. Keep overall POC partial.

## Final evaluation 4.0

- Reused the running Pixel 9 Pro AVD (`emulator-5554`) and installed the ZITADEL-specific x86_64 debug APK. The Android application ID is `com.example.kunde_mobile`. The AppAuth callback is separately registered as `com.kunde.mobile:/oauth2redirect`.
- Compose confirmed existing ZITADEL 4.19.5 services healthy in 10 seconds. The host discovery document advertised exact issuer `http://localhost:8280`, authorization `/oauth/v2/authorize`, token `/oauth/v2/token`, JWKS `/oauth/v2/keys` and end-session `/oidc/v1/end_session`; the JWKS contained two keys.
- ZITADEL Login V2 rendered the synthetic-account form in Chrome Custom Tab through `adb reverse tcp:8280 tcp:8280`. The existing Keycloak 8180 and API 8080 mappings were preserved. The ZITADEL API mapping is `adb reverse tcp:8082 tcp:18082`. Host 8082 was unavailable when replacing the original runtime, so the new Spring process listens on host loopback 18082.
- An Android HTTP probe through the same reverse mapping returned HTTP 200 for discovery and JWKS. Discovery reported the same issuer and endpoints as on the host.
- The unrelated Pixel Launcher ANR initially obscured Flutter and Chrome. Closing that overlay exposed the browser. An Android Back input cancelled the Custom Tab and Flutter reported `FlutterAppAuthUserCancelledException`. This is a directly observed cancellation result.
- The independent protocol probe used provider Session and OIDC APIs for the synthetic login, with an S256 verifier and the same native redirect URI. It exchanged a real authorization code and received a signed JWT access token. The issuer matched exactly and the signing `kid` appeared in live JWKS. This probe is distinct from the Flutter callback.

| Android action | Observed 4.0 outcome |
|---|---|
| Sign in with system browser | Chrome Custom Tab opened on `localhost:8280`. ZITADEL accepted the synthetic credentials. |
| Native callback and exchange | Flutter reported **Authorization Code + PKCE completed**. |
| Protected API | Flutter reported **API returned HTTP 200** against the Spring instance configured for ZITADEL. |
| Refresh and repeat API | Flutter reported **Refresh completed**, then **API returned HTTP 200**. |
| Logout | Flutter reported **Local tokens cleared; provider logout requested** after the end-session return. |
| Next authorization | Selecting the remembered account required the password. Flutter completed a second PKCE exchange and the API returned HTTP 200. A second logout cleared local tokens. |

See [security results](security-results.md#final-evaluation-40) for per-case HTTP outcomes and evidence limits.
