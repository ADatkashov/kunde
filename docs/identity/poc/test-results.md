# Identity POC test results — recovery 3.0

Execution date: 2026-11-10 (local Windows development environment). Synthetic identity only; no production services or customer data used. This supersedes the previous “verification 2.0” outcome where appropriate.

## Evidence summary

| Check | Result | Evidence / boundary |
|---|---|---|
| Secure Maven TLS and backend suite | PASS, carried forward | Java 21, Maven 3.9.9, Spring Boot 3.5.7; `mvn verify`: 21 tests, 0 failures/errors/skips. TLS bootstrap uses Windows-trusted certificates and JSSE verification. See `maven-tls.md`; run scripts in PowerShell 7 (`pwsh`). Not repeated in this recovery because it had already passed. |
| Android environment and networking | PASS | Pixel 9 Pro AVD, Android 37.1 Google Play x86_64, emulator-5554. `adb reverse tcp:8180 tcp:8180` preserves the exact `localhost` Keycloak issuer; reverse 8080 routes API. Chrome displayed issuer discovery JSON. See `android-networking.md`. |
| Keycloak health/discovery/JWKS | PASS | Pinned Keycloak 26.8.2; issuer `http://localhost:8180/realms/kunde-dev`; host-only port mapping, discovery and JWKS were reachable. |
| Keycloak Android system-browser PKCE | PASS | Chrome Custom Tab showed login form; synthetic user authenticated; AppAuth returned to Flutter and status showed “Authorization Code + PKCE completed”. See evidence index and screenshots in `.local/`. |
| Keycloak real access JWT → Spring API | PASS | Live Spring Security validated provider signature, issuer, `kunde-api` audience, expiry and `kunde.poc`; `GET /api/v1/poc/whoami` returned HTTP 200 and `authenticated:true`. No raw token logged or documented. |
| Keycloak refresh | PASS | Flutter refresh action completed; subsequent protected API call returned 200. This proves renewal in this session, not refresh-token replay policy. |
| Keycloak logout/re-login | PASS, browser session evidence | Flutter reported local tokens cleared/provider logout requested. A new authorization displayed the username/password form, evidencing the prior browser SSO session was no longer silently reused. Re-login was opened; a second completed login after logout was not captured. |
| ZITADEL containers/discovery/JWKS | PASS for service readiness/metadata | ZITADEL 4.19.5 startup and health checks passed in 96.1 s; issuer `http://localhost:8280`, authorization `/oauth/v2/authorize`, token `/oauth/v2/token`, JWKS `/oauth/v2/keys`, end-session `/oidc/v1/end_session`. Android/provider client was not configured; no user-backed E2E. |
| Spring deterministic JWT matrix | PASS, fixture only | Six existing HTTP integration tests cover valid/missing/invalid signature/wrong issuer/wrong audience/time/permission and JWKS cache/new-kid behavior. This does not substitute for unrun live negative-token cases. |
| Maven and Flutter test suites | PASS, prior run | Flutter analyze clean; four existing unit tests passed. No redundant rerun in recovery. |

## Troubleshooting findings

1. The emulator is a separate namespace. Replacing only one `localhost` endpoint with `10.0.2.2` would make discovery issuer inconsistent with issuer validation. Host ports bind to loopback; `adb reverse` is the compatible local solution for provider and API while preserving metadata issuer.
2. The earlier `invalid scopes` response followed a stale Keycloak realm in the persisted database: Compose import did not overwrite an initialized realm. The live realm lacked optional `offline_access`; this was added, and Flutter now requests only scopes configured for this client.
3. Keycloak accepted the token but the POC controller returned 500 when `sub` was absent and `Map.of` rejected a null value. The Keycloak 26 client lacked a Subject mapper. A standard `basic` client scope with `oidc-sub-mapper` was added and assigned by default; the same real-token flow then returned HTTP 200. The controller now safely emits a nullable subject and logs claim names/presence only.
4. Chrome first-run UI and a preloaded unrelated app's ANR dialog obscured initial login attempts. After completing Chrome setup and dismissing the dialog, the Keycloak login page rendered normally. See `pkce-debugging.md`.

## Reproduction

Use PowerShell 7. Start the provider, connect emulator ports, run backend with POC profile, and build Flutter using `OIDC_ISSUER=http://localhost:8180/realms/kunde-dev`, `OIDC_CLIENT_ID=kunde-consumer-poc`, redirect `com.kunde.mobile:/oauth2redirect`, scopes `openid offline_access kunde.poc`; API URL may be `http://localhost:8080/api/v1/poc/whoami` with reverse 8080 (or `10.0.2.2` for API only). Exact safe networking details are in `android-networking.md`.

POC verification is **partial overall**: Keycloak’s principal end-to-end path succeeded; ZITADEL’s equivalent path, full lifecycle, and provider-backed negative security matrix remain open. Keep ADR-015 PROPOSED; TASK-005 pending explicit provider approval and TASK-006 not complete.
