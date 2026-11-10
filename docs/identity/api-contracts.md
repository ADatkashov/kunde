# Proposed API contracts

This contract distinguishes OAuth/IdP-owned endpoints from KUNDE APIs. Exact paths and error envelope must be reconciled with existing API versioning before implementation. Never implement a parallel endpoint that issues KUNDE tokens.

## OIDC endpoints owned by the selected IdP

| Operation | Method / endpoint | Client auth | Contract notes |
|---|---|---|---|
| Discovery | `GET /.well-known/openid-configuration` | Public | Flutter/API trust only preconfigured issuer; verify returned issuer. |
| Authorize | `GET /authorize` | Public client + PKCE | System browser; `response_type=code`, exact redirect, `state`, `nonce`, `code_challenge=S256`, scopes. No wildcard redirect. |
| OTP start/verify | Vendor login UI/API | Per IdP flow | IdP owns challenge; generic result; rate limited; exact error semantics verified in POC. Do not expose vendor paths as KUNDE API contract. |
| Token/refresh | `POST /token` | Public client with verifier for code exchange | Authorization code and PKCE; refresh rotation/reuse detection. TLS form body; redact. |
| Revoke/end session | OIDC revocation/end-session endpoints | As specified by IdP | Logout local device, optionally all sessions; logout does not rely on deleting local token only. |

## KUNDE-owned authenticated API

Envelope proposal: errors use stable `code`, localized-safe `message`, `correlationId`, optional `retryAfterSeconds`; never include user existence or provider secrets. All protected endpoints validate bearer access token and domain permissions.

| Method / path | Purpose / body | Auth and validation | Response / errors / abuse controls |
|---|---|---|---|
| `GET /api/v1/me` | Current KUNDE profile and coarse capabilities | Access token for KUNDE API; resolve `iss+sub` | `200 {userId,displayName,locale,contacts,accountStatus}`; `401/403`; no phone as key. |
| `GET /api/v1/me/sessions` | List sessions/devices | Fresh identity mapping; owner only | `200 [{sessionId,deviceLabel,createdAt,lastSeenAt,current}]`; never expose raw refresh token. |
| `DELETE /api/v1/me/sessions/{sessionId}` | Revoke one session | Owner + fresh auth for other-session revoke | `204`; `404` generic; `409` if provider revoke pending; rate limit and audit. |
| `POST /api/v1/me/phone-change-challenges` | `{newPhone, channel}`; request IdP challenge for authenticated change | Current account + recent reauth; normalize E.164, country range and allowlist channel | `202 {challengeId,expiresAt,resendAvailableAt}` with same shape for duplicate/existing number; rate limit per user/phone/IP; no provider name. |
| `POST /api/v1/me/phone-change-challenges/{id}/verify` | `{code}` | Owner, challenge bound to account+new phone, unexpired, one-use, max attempts | `200 {status:"verified"}`; generic `400/410/429`; code never logged; update contact only after IdP proof. |
| `GET /api/v1/me/identity-links` | List linked sign-in methods (safe labels only) | Owner + recent auth | `200 [{type,maskedLabel,verifiedAt}]`; no subject or provider credential. |
| `POST /api/v1/me/identity-links` | `{provider, redirectContext}` start link; complete through IdP OIDC step-up callback | Recent auth to existing account and proof new identity | `202 {authorizationUrl/stateHandle}` or IdP redirect; conflict requires secure recovery, never auto-merge. |
| `DELETE /api/v1/me/identity-links/{linkId}` | Unlink one method | Recent auth + ensure at least one recovery method remains | `204`; `409` last credential; notify user and audit. |
| `POST /api/v1/me/account-deletion-requests` | `{confirmation:true}` | Recent auth; explicit irreversible-action confirmation | `202 {requestId,status,availableUntil}`; idempotency key required; 409/422 for retention/legal hold with neutral explanation. |

## No standalone public registration/login API

New account creation, OTP submission, token exchange and refresh stay in the selected IdP flow. If the approved provider cannot expose KUNDE-branded, anti-enumerating phone flow safely, pause implementation and revise ADR; do not create `/auth/verify` in Spring that mints tokens.

## Common requirements

- `Idempotency-Key` on account-deletion and other irreversible command requests; stable response on retry.
- `X-Correlation-ID` accepted only as a bounded opaque value or replaced server-side.
- Rate limits are layered: account, phone, IP, device and global; `429` with `Retry-After`, no sensitive account-existence detail.
- Phone changes create KUNDE audit event and provider revocation/outbox work; retries are safe and observable.
