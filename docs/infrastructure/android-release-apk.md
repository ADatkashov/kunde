# Android Release APK (DEV only)

Workflow `android-release.yml` (manual) builds `KUNDE-dev-release.apk`: `flutter build apk --release`, arm64, API
`https://kunde-backend-5wwg.onrender.com/api/v1/` via `--dart-define=API_BASE_URL`, 90 s request timeout (Render Free cold start ~1 min).
Release signing is read only from environment variables; without them the release build fails (no debug-key fallback).

## One-time owner setup (keystore is not in Git)
1. Run `scripts/android/generate-release-keystore.sh` locally; **back up** the `.jks` and password (needed for every future update).
2. Add repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`kunde-dev`), `ANDROID_KEY_PASSWORD`.
3. Actions → *Android Release APK (DEV)* → Run workflow; download artifact `KUNDE-dev-release` (kept 14 days) and check `.sha256`.
4. Install: allow "install unknown apps", open the APK.

## Phone sign-in (ADR-015 amended 2026-11-14)
The build uses `--dart-define=PHONE_AUTH_ENABLED=true` (own phone-OTP login, no identity provider) and, by default, `DEV_OTP_HINT=true`
(shows "Test code: 123456" on the code screen; workflow input `dev-otp-hint`). Sign-in only works once the backend has phone auth enabled; see
[phone-otp-auth.md](../identity/phone-otp-auth.md#dev-setup) (Render env vars via the Terraform workflow, owner-approved apply).
Use only the synthetic numbers in the allowlist (default `+7 700 000 00 01`..`03`). The workflow verifies the APK contains the auth endpoints.

## Limits
- Without the backend variables above, `/auth/*` answers 503 and sign-in fails closed; only public catalog screens work.
- applicationId stays `com.example.kunde_mobile` (changing it affects the native E2E harness); decide before any store release.
- Not verified on a physical device.
