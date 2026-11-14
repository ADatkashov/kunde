# Android Release APK (DEV only)

Workflow `android-release.yml` (manual) builds `KUNDE-dev-release.apk`: `flutter build apk --release`, arm64, API
`https://kunde-backend-5wwg.onrender.com/api/v1/` via `--dart-define=API_BASE_URL`, 90 s request timeout (Render Free cold start ~1 min).
Release signing is read only from environment variables; without them the release build fails (no debug-key fallback).

## One-time owner setup (keystore is not in Git)
1. Run `scripts/android/generate-release-keystore.sh` locally; **back up** the `.jks` and password (needed for every future update).
2. Add repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`kunde-dev`), `ANDROID_KEY_PASSWORD`.
3. Actions → *Android Release APK (DEV)* → Run workflow; download artifact `KUNDE-dev-release` (kept 14 days) and check `.sha256`.
4. Install: allow "install unknown apps", open the APK.

## Limits
- Login is enabled only when the GitHub variable `OIDC_ISSUER_URI` (plus `OIDC_CLIENT_ID`, `OIDC_PROJECT_ID`) is set; see [ZITADEL DEV runbook](../identity/zitadel-dev.md). Without it identity is off in this build (`CONSUMER_IDENTITY_ENABLED` unset): no identity provider is deployed in DEV, so profile/consent/addresses/support
  (protected endpoints return 503 fail-closed) are not usable; only public catalog screens work. Login needs an approved IdP (ADR-013/015) first.
- applicationId stays `com.example.kunde_mobile` (changing it affects the native E2E harness); decide before any store release.
- Not verified on a physical device.
