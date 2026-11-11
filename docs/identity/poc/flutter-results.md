# Flutter integration results — recovery 3.0

**4.0 result.** ZITADEL passed Chrome Custom Tab PKCE, native callback, Flutter code exchange, protected API HTTP 200, refresh and another HTTP 200 on the same AVD. Logout returned to Flutter and cleared local tokens. Selecting the remembered account required the password. The second completed login again reached API HTTP 200. AppAuth also reported user cancellation when a Back input closed the Custom Tab in an earlier attempt. See the [4.0 end-to-end evidence](end-to-end-evidence.md#final-evaluation-40). The sections below retain the 3.0 Keycloak baseline.

## Keycloak real-device-emulator flow

Verified on the existing Pixel 9 Pro AVD (Android 37.1 Google Play x86_64, emulator-5554). The debug app launched, AppAuth opened Chrome Custom Tab, the synthetic user authenticated, and Flutter displayed **Authorization Code + PKCE completed**. The callback was `com.kunde.mobile:/oauth2redirect`; Android's merged manifest contains AppAuth's redirect receiver for `com.kunde.mobile`. The Flutter app exchanged the code and held an authenticated session; it called the live Spring protected endpoint and received HTTP 200. See `end-to-end-evidence.md` and screenshots in `.local/`.

The real Keycloak token contained issuer `http://localhost:8180/realms/kunde-dev`, audience `kunde-api` and scope `kunde.poc`; Spring validated it. Token contents and credentials are intentionally not stored in logs or docs.

Refresh completed successfully and the next API call returned 200. Flutter logout reported local tokens cleared and provider logout requested. A subsequent browser authorization presented the login form, showing no silent SSO reuse from the previous browser session. The second login was launched but not completed in retained evidence. Existing JWT invalidation after logout was not tested; self-contained access JWTs generally remain acceptable to this resource server until expiration unless additional revocation/session checks are added.

## Other checks and limits

Earlier `flutter analyze` passed with no issues; four existing Flutter tests passed, but do not exercise OIDC. These were not rerun unnecessarily. No APK-build result is used as authentication evidence. ZITADEL app/project setup remains incomplete, so no ZITADEL browser callback, exchange, refresh or API call was tested. Invalid state/callback, cancellation, network failure, expired refresh token, access expiry recovery, token replay and secure-storage inspection remain unverified.

The app has no embedded client secret, uses OS browser/AppAuth, stores refresh/ID tokens in secure storage and keeps the access token in memory. Local HTTP is allowed only for the identity POC and loopback issuer; release/default config stays HTTPS-only. Do not use embedded WebView or Resource Owner Password Credentials.

## Reproduce Android connectivity/build

```powershell
adb reverse tcp:8180 tcp:8180
adb reverse tcp:8080 tcp:8080
cd mobile
flutter build apk --debug --split-per-abi --target-platform android-x64 `
  --dart-define=IDENTITY_POC_ENABLED=true `
  --dart-define=OIDC_ISSUER=http://localhost:8180/realms/kunde-dev `
  --dart-define=OIDC_CLIENT_ID=kunde-consumer-poc `
  --dart-define=OIDC_REDIRECT_URI=com.kunde.mobile:/oauth2redirect `
  --dart-define="OIDC_SCOPES=openid offline_access kunde.poc" `
  --dart-define=IDENTITY_POC_API_URL=http://localhost:8080/api/v1/poc/whoami
```

See `android-networking.md`, `pkce-debugging.md`, and `end-to-end-evidence.md` for tested results.
