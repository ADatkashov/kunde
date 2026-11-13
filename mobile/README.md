# KUNDE Consumer App

Flutter/Dart foundation shell. It reads `/api/v1/capabilities`, shows connection state, and does not advertise categories, sign-in or AI while those capabilities are unavailable. A category search field appears only when the server reports the marketplace enabled; results come only from `GET /api/v1/search`.

## Run

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1/
```

Use `http://localhost:8080/api/v1/` for desktop/local host or the host-reachable API URL on a physical device. Use HTTPS outside local development. The API URL is public configuration, not a secret. Current strings include Russian, Kazakh and English scaffolding; official launch language is not decided.

Android and iOS platform scaffolding is included. Android permits cleartext only in the debug manifest for local emulator API traffic; release signing remains unset. Replace generated bundle identifiers with the approved publisher identity before store distribution.

## Consumer authentication

[Consumer setup and verification](../docs/identity/consumer-validation/README.md)
documents the explicit `CONSUMER_IDENTITY_ENABLED`, `OIDC_ISSUER_URI`,
`OIDC_CLIENT_ID` and HTTPS `API_BASE_URL` dart-defines. Enabled builds use real
system-browser AppAuth, platform secure storage, session restore and profile UI.
The default foundation shell and isolated POC remain available when Consumer
identity is disabled. Tests use injected doubles only under `test/`.
