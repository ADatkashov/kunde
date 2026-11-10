# PKCE debugging notes — recovery 3.0

## Successful path

On Pixel 9 Pro AVD, Flutter AppAuth opened a Chrome Custom Tab, the Keycloak synthetic user login rendered, authorization returned to the app's `com.kunde.mobile:/oauth2redirect`, and Flutter reported **Authorization Code + PKCE completed**. The authorization code was exchanged by AppAuth; the resulting access JWT reached Spring and received HTTP 200. Evidence and sanitized screenshots: `end-to-end-evidence.md` and ignored `.local/` files.

## Root causes found

1. **Invalid scope:** an initialized Keycloak database already contained an older realm. `--import-realm` did not overwrite it; the live public client lacked optional `offline_access`. The first response was `invalid scopes`. The live realm was updated to assign `offline_access` as optional, and the app's request was reduced to configured `openid offline_access kunde.poc`. Do not assume editing an import file changes an existing realm.
2. **Blank Chrome/loading screen:** Chrome was on first-run setup; an unrelated preinstalled app ANR/system dialog also obscured interaction. After completing Chrome setup and dismissing the overlay, the Keycloak form loaded normally. Earlier coordinate taps and login submission had targeted the wrong positions. Capture screenshots before automating taps.
3. **API HTTP 500 after successful login:** Spring accepted the provider JWT, but its access token had no `sub`; the POC controller used `Map.of`, which throws on null. Claim-presence-only diagnostics isolated the issue. The Keycloak 26 realm had no Subject (`sub`) mapper in the assigned `basic` scope. Added `oidc-sub-mapper` to default `basic` scope and assigned the scope to the public client. Subsequent token exposed subject and API returned 200. Keep token diagnostics value-free.
4. **Expired access token:** a later API attempt after several minutes returned 401 as designed. Flutter refresh renewed it; the following call returned 200. Do not interpret access-token expiry as a network or issuer failure.

## Repro checklist

1. Start Keycloak and backend locally, confirm health, install/launch APK and apply `adb reverse` rules from `android-networking.md`.
2. Check OIDC discovery issuer equals the configured Flutter issuer exactly. Confirm realm/client exists in the persistent database.
3. Check valid redirect, enabled standard flow, PKCE S256, no secret, assigned scopes and optional `offline_access`; request only scopes actually configured.
4. Ensure Chrome Custom Tabs initialized and visible; inspect login page and OS callback activity. Confirm AppAuth receiver scheme and Flutter app resume.
5. Confirm success status without printing tokens. Call the protected API. HTTP 401 suggests missing/expired/invalid JWT; 403 suggests authorization scope/permission; 500 required server-side diagnosis (here it was a null claim response bug).
6. Refresh once, call API again, then logout and verify a subsequent authorization interaction. Treat token/session/revocation semantics separately.

The code verifier/state/code were not recorded. Invalid callback/state/cancellation and network interruption were not separately executed; do not infer their negative behavior from a successful transaction.
