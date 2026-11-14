# ZITADEL Cloud Free for KUNDE DEV (owner runbook)

Scope: DEV with **synthetic users only**. Production provider is **not** chosen (ADR-015 gates stay open).
Free plan (per [zitadel.com/pricing](https://zitadel.com/pricing), checked 2026-11-14 via search; re-check before relying on it): $0/month, 100 daily active users,
unlimited stored users, EU/US/CH/AU data location. DAU counts any user who authenticates or refreshes that day, service users included.
No credit card should be needed; do not choose a paid plan. Issuer is `https://<instance>.zitadel.cloud` (no custom domain on Free).

## One-time console steps (owner, ~15 min)
1. Create a ZITADEL Cloud account and an instance (region EU) on the **Free** plan.
2. Project `kunde` → note the **Project ID** (`OIDC_PROJECT_ID`).
3. In the project, add an application: type **Native**, auth method **PKCE** (no client secret), name `kunde-consumer`.
   - Redirect URI: `com.kunde.mobile:/oauth2redirect`; Post logout URI: `com.kunde.mobile:/oauth2redirect`.
   - Token settings: **Auth Token Type = JWT** (the backend validates signed JWTs; opaque tokens will be rejected), enable
     *Refresh token*, and *Add user roles/info to ID token* is not needed.
   - Note the generated **Client ID** (public, `OIDC_CLIENT_ID`).
4. Project settings: enable *Assert roles on authentication* off, and *Check authorization on authentication* off for DEV (no roles are used).
5. Create 1–2 **synthetic** human users (`dev-user-1@example.invalid`, strong random password, no real data). Self-registration may stay enabled for the
   in-app "register" button (`prompt=create`).
6. GitHub → Settings → Secrets and variables → Actions → **Variables** (public values, not secrets):
   `OIDC_ISSUER_URI` (e.g. `https://kunde-dev-abc123.zitadel.cloud`), `OIDC_CLIENT_ID`, `OIDC_PROJECT_ID`, `OIDC_AUDIENCE` (= Project ID),
   `CONSUMER_IDENTITY_ENABLED` = `true`.
7. Apply the backend change only after reviewing the plan: run `terraform-dev.yml` (plan), then apply with `replace_render=true` (separate explicit permission).
8. Run **Android Release APK (DEV)**; it enables login when `OIDC_ISSUER_URI` is set.

## How it fits the code
- Mobile: Authorization Code + PKCE via system browser (`flutter_appauth`), scopes `openid profile offline_access urn:zitadel:iam:org:project:id:<ProjectID>:aud`
  (the audience scope puts the project id into `aud`; `offline_access` is needed for refresh tokens). Build defines: `CONSUMER_IDENTITY_ENABLED`, `OIDC_PROVIDER=zitadel`,
  `OIDC_ISSUER_URI`, `OIDC_CLIENT_ID`, `OIDC_SCOPES`.
- Backend (Render env): `OIDC_ISSUER_URI`, `OIDC_AUDIENCE` (= Project ID), `CONSUMER_IDENTITY_ENABLED=true`, `CONSUMER_CLIENT_ID` (= Client ID), `OIDC_TOKEN_PROFILE=zitadel`.
  Spring still enforces signature, exact issuer, audience and time; `ConsumerAccessPolicy` (profile `zitadel`) additionally requires `client_id` = the consumer client and rejects ID tokens.
  ZITADEL has no custom scopes, so `kunde.consumer` is not used under this profile.
- Nothing secret is stored in Git or GitHub: client id, issuer and project id are public identifiers; there is no client secret.

## Not verified
No live ZITADEL tenant was used in this change: claim shape (`client_id`, `aud`, `scope`) follows ZITADEL JWT access-token documentation and is covered only by unit tests.
The first real login on a phone is the real verification; failures should be reported with the HTTP status and `error` code, never with tokens.
