# Token architecture

## Token roles

- **ID token:** proves sign-in to the OIDC client; never use as a KUNDE API bearer credential.
- **Access token:** short-lived authorization credential, audience restricted to the intended KUNDE API/resource. API accepts only configured issuer, key/algorithm, audience and time bounds.
- **Refresh token:** long-lived secret for the public native client; rotate on use with reuse detection or use sender constraint if supported. Keep only in secure OS storage.
- **Service token:** separate workload identity for backend-to-backend calls; no end-user refresh token or static secret in Flutter.

## Proposed claim contract

Require standard `iss`, `sub`, `aud`, `exp`, `iat`, and `nbf` when present/required by policy; validate signature and exact issuer/audience. `azp`/client ID allowlist limits approved clients. `jti` supports correlation, not a revocation guarantee by itself. For elevated actions use fresh `auth_time` and policy `acr`/`amr` verified against provider semantics. The API maps `iss + sub` to KUNDE ID. Minimize PII claims. Treat `scope` as coarse API capability and still perform resource checks.

## Lifetime and revocation proposal

Starting defaults for POC: consumer access token 5–10 minutes; privileged/admin 5 minutes; refresh session idle/absolute bounds selected with product after offline-UX testing. These are design targets, not provider defaults. Revoke refresh family on logout/device removal, password/phone compromise, account suspension and refresh reuse. Stateless JWTs may remain usable until expiry unless API checks revocation/session state; document this residual window and use shorter lifetime for high-risk operations.

## Rotation and keys

Use OIDC discovery from fixed configured issuer over TLS; cache JWKS with bounded TTL; accept overlapping old/new signing keys during rotation and refresh once on unknown `kid` with rate limits. A valid signature from an unapproved issuer remains invalid. Treat provider outage as temporary auth failure; never disable issuer/audience validation. Key rollover and emergency signing-key compromise require tested procedures and alerts.

## Transport and storage

Bearer token only in `Authorization` header over TLS, never query strings, analytics or logs. No client secret in mobile app. Flutter refresh token in Keychain/Android Keystore-backed storage; access token in memory. Do not put access/refresh tokens in crash reports. Ensure reverse proxy logs redact authorization headers.
