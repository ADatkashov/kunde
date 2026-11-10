# Android emulator networking — identity POC

## Tested topology

The Pixel 9 Pro emulator has an isolated network namespace. Compose binds Keycloak to host `127.0.0.1:8180`; its issuer and discovery advertise `http://localhost:8180/realms/kunde-dev`. The backend uses strict issuer equality against that value. Rewriting only the issuer to `10.0.2.2` would cause issuer mismatch because discovery/JWKS and authorization/token endpoints still advertise `localhost`.

This POC uses Android Debug Bridge reverse port forwarding. It preserves `localhost` consistently for browser, app, and provider while keeping host services bound to loopback:

```powershell
adb devices
adb reverse tcp:8180 tcp:8180  # Keycloak; issuer remains localhost
adb reverse tcp:8080 tcp:8080  # Spring API, if app API URL uses localhost
adb reverse --list
```

Observed on emulator `emulator-5554`: Chrome loaded Keycloak discovery JSON from `http://localhost:8180/realms/kunde-dev/.well-known/openid-configuration`; the PKCE flow completed. The app called Spring Boot and received HTTP 200. Screenshot evidence is under ignored `docs/identity/poc/.local/`.

`10.0.2.2` is the emulator's special route to the host loopback and is acceptable for the API endpoint by itself. It must not be substituted into the issuer or used to rewrite metadata URLs. The earlier APK used `http://10.0.2.2:8080` for the API; reverse-forwarding 8080 and using `http://localhost:8080` is more uniform. Confirm the app's API URL and active reverse mappings after rebuild.

## Constraints and diagnostics

- Keep compose published ports on `127.0.0.1`; do not bind to `0.0.0.0` or LAN interfaces.
- No public or production domain is needed. No insecure issuer validation is permitted.
- Android redirect remains `com.kunde.mobile:/oauth2redirect`, not an HTTP host callback. The Android manifest's AppAuth redirect receiver must match scheme `com.kunde.mobile`.
- Keycloak local HTTP cleartext allowance exists only in the debug POC manifest and is further guarded by Flutter's loopback issuer check. Release/default behavior remains HTTPS-only.
- Chrome Custom Tab uses the system browser. Finish Chrome first-run setup before tests; dismiss unrelated system/ANR dialogs.
- Check discovery's `issuer`, `authorization_endpoint`, `token_endpoint` and `jwks_uri` all resolve using the same host spelling. Probe from host and emulator separately. A TCP connection alone does not prove HTTP, OIDC or callback functionality.
- `localhost` may resolve to IPv6 `::1` and IPv4 `127.0.0.1`; keep the service listening/published on host loopback and use ADB reverse instead of guessing which address the emulator selects. Validate the actual URL in Chrome and Flutter logs.

## ZITADEL

The local ZITADEL proxy binds `127.0.0.1:8280` and advertises issuer `http://localhost:8280`. Equivalent mapping is `adb reverse tcp:8280 tcp:8280`. Its service health and discovery passed, but no configured Android client flow was completed. See `zitadel-setup.md`.
