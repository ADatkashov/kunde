# KUNDE Partner — Android release APK (DEV)

Workflow `.github/workflows/partner-release.yml` (manual, `workflow_dispatch`) builds `KUNDE-Partner-dev-release.apk`:
signed release, arm64, DEV API `https://kunde-backend-ty81.onrender.com/api/v1/`, 90 s request timeout (Render Free cold start ≈ 1 min).
It runs `flutter analyze --fatal-infos` and `flutter test` first.

## Identity

| | Partner | Consumer |
|---|---|---|
| applicationId | `com.kunde.kunde_partner` | `com.example.kunde_mobile` |
| Launcher label | KUNDE Partner | KUNDE |
| Workflow / artifact | `partner-release.yml` / `KUNDE-Partner-dev-release` | `android-release.yml` / `KUNDE-dev-release` |

The two apps install side by side. The Android scaffold is committed in `partner_app/android/` (no `flutter create` at build time).

## Signing

Same repository secrets as the Consumer release (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`);
they are only read from the environment in the build job, the keystore is written to the runner temp directory and deleted, nothing is logged or committed.
Gradle refuses `assembleRelease` without them (no debug-key fallback). Missing secrets fail the first workflow step with the name of the missing secret.

## Verification performed by the workflow

`apksigner verify` (v2/v3, not the Android Debug certificate), `aapt` badging: package `com.kunde.kunde_partner`, label `KUNDE Partner`, `INTERNET`, not debuggable,
not the Consumer package; `lib/arm64-v8a/libapp.so` present and containing the DEV API host and `auth/otp/verify`; no localhost/emulator URL and no private-key marker;
SHA-256 written next to the APK (artifact kept 14 days).

## Installing over an earlier debug APK

The earlier `KUNDE-Partner-DEV-debug-APK` (PR workflow, debug certificate) has the same package id but another signature: uninstall it before installing the signed
release APK (settings and session live in the app, nothing server-side is lost). Later release builds update in place as long as the same keystore is used.

## DEV only

`DEV_OTP_HINT=true` (workflow input, default true for DEV) shows the synthetic demo code on the OTP screen. Never enable it, nor a DEV API URL, for a store/production build.
Production build, store signing, push and PROD API remain gated (see `docs/product/partner-app.md`).
