# Flutter integration specification

## Flow and package boundary

Use a maintained OIDC Authorization Code + PKCE library with external system browser, exact callback, `state`, `nonce` and issuer validation. Evaluate Flutter package maintenance and platform support at implementation time. Universal Links / Android App Links are preferred over unclaimed custom schemes. Never use an embedded WebView, client secret or Resource Owner Password grant. Keep an `AuthRepository` interface separate from profile/domain repositories so IdP SDK can be replaced.

## Screens and states

Phone entry with country selector, RU/KK/EN labels and accessible numeric keypad; consent/privacy explanation; sending state; code entry with masked destination and countdown; resend disabled until cooldown; expired/invalid generic error; network/offline retry state; account restricted/support path; successful transition; session expired reauthentication; device/session list and revoke; phone/email change with fresh auth; logout. Keep account enumeration-resistant copy and never reveal whether a number already has an account.

## Session handling

Hold access token in memory; persist rotating refresh token only in Keychain/Android Keystore-backed secure storage. On refresh reuse/rejection clear local tokens and require sign-in. Lock screenshots/clipboard only where justified and platform-appropriate; do not copy OTP automatically unless OS autofill is safe. Clear local session and caches on logout; server revocation should be requested before local cleanup, but local logout must complete even offline and queue a revocation intent safely.

## Deep links, accessibility and localization

Validate callback state/nonce and expected issuer/client, handle duplicate callbacks idempotently, reject unexpected host/path and avoid token-bearing URLs in logs. RU, KK, EN strings must not concatenate phone digits or code fragments incorrectly; verify plural forms, screen-reader labels, focus order, contrast, text scaling, paste/autofill behavior and localized error announcements. Honor design tokens and interaction states in `docs/design/`.

## Offline / errors

No offline authentication to protected APIs. Clearly distinguish offline cached non-sensitive content from authenticated actions. Retry idempotent reads; do not auto-resend paid OTP on network timeout without checking request state. Keep error details actionable but generic.
