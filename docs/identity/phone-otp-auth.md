# Phone OTP authentication (ADR-015, amended 2026-11-14)

Own authentication in the Spring Boot monolith: phone number, one-time code, access JWT, rotating refresh token. DEV uses a fixed test code for synthetic numbers; real SMS/WhatsApp delivery is **not** connected. Off by default (`AUTH_PHONE_ENABLED=false`); production use is gated (see end).

## API (`/api/v1`, JSON, `Cache-Control: no-store`)

| Endpoint | Body | Success | Failures |
|---|---|---|---|
| `POST /auth/otp/request` | `{"phone": "+7 700 000 00 01"}` | `202 {"expiresInSeconds":300,"resendAfterSeconds":30}` — identical for every well-formed number | `400 INVALID_PHONE`, `429 OTP_RATE_LIMITED`, `503 OTP_DELIVERY_UNAVAILABLE` |
| `POST /auth/otp/verify` | `{"phone","code":"123456"}` | `200 {accessToken, refreshToken, tokenType:"Bearer", expiresIn, refreshExpiresIn}` | `400 INVALID_REQUEST`, `401 INVALID_CODE` (wrong, expired, locked, unknown — indistinguishable), `403 ACCOUNT_UNAVAILABLE` |
| `POST /auth/token/refresh` | `{"refreshToken"}` | new access + refresh token; the old refresh token is spent | `401 INVALID_REFRESH_TOKEN` |
| `POST /auth/logout` | `{"refreshToken"}` | `204`, idempotent (unknown token also 204) | — |

Phones are normalized to E.164 (`+7 700…`, `8 700…`, `7 700…`, `00…` accepted). Protected routes (`/me`, `/me/consents`, `/me/addresses`, `/me/support/cases`) are unchanged and take `Authorization: Bearer <accessToken>`.

## Security controls

- **No account enumeration:** a request creates a challenge for any well-formed number and answers identically; a number outside the DEV allowlist simply gets a code nobody can read. All verify failures return the same `INVALID_CODE`.
- **OTP:** 6 digits, 300 s TTL, stored only as `HMAC-SHA256(otpKey, phone|challengeId|code)`, constant-time compare, max 5 attempts then the challenge is burned, only the newest challenge can succeed, one-time use. Request limits per number (DB-backed, restart-safe): 30 s cooldown, 3 per 10 min, 10 per day.
- **Access token:** HS256 JWT, 900 s, claims `iss=kunde-phone-auth`, `sub=<KUNDE user UUID>`, `aud=kunde-api`, `sid`, `azp=kunde-consumer`, `scope=kunde.consumer`, `typ=Bearer`, `jti`. The resource server validates signature, exact issuer, audience, time, required claims, **and that the server session is live** (`sid`), so logout and replay revocation are immediate. The existing `ConsumerAccessPolicy` still applies.
- **Refresh token:** 256-bit random, only its keyed hash is stored, rotated on every use (30 days, session cap 90 days). Presenting an already-used token revokes the whole session (`REFRESH_REPLAY`). A response lost in transit after rotation therefore forces a new login — intentionally strict.
- **Keys:** one secret `AUTH_PHONE_SECRET` (≥ 32 chars) is expanded by HMAC into separate JWT / OTP / refresh / audit sub-keys. Never committed or logged.
- **Audit:** `identity.auth_events` (OTP requested/failed/locked/verified, session, refresh, replay, logout) keyed by a keyed phone hash, never the number, code or token. Tokens and codes are not logged; tests assert that.
- **Fail-closed startup (`PhoneAuthGuard`):** enabled flag with a short secret, together with `OIDC_ISSUER_URI`, or with out-of-range lifetimes aborts startup. Without a DEV provider the delivery provider is `DisabledOtpProvider` and OTP requests return 503.
- **Request surface:** existing body-size and per-IP limits apply to `/auth/*`.

## DEV OTP rules

`123456` is accepted only when **all** hold: `AUTH_PHONE_ENABLED=true`, `AUTH_DEV_OTP_ENABLED=true`, `KUNDE_ENVIRONMENT` is `dev`/`local`/`test` (default is `production`), no `prod`/`production` Spring profile, and the number is in `AUTH_DEV_OTP_ALLOWED_PHONES` (max 20, each `+7700000XXXX`; plausible real numbers are rejected at startup). Anything else aborts startup. Nothing is delivered, and nothing about it is logged. Never use real phone numbers in DEV.

## Data model (Flyway V9)

`identity.phone_identities` (user ↔ E.164 phone, unique), `identity.otp_challenges`, `identity.auth_sessions`, `identity.refresh_tokens`, `identity.auth_events`. A new user is created at first successful verification together with its `identity.external_bindings(issuer, subject)` row and `profile.consumer_profiles`. E.164 phone numbers are personal data: DEV holds synthetic numbers only.

## DEV setup

Owner actions (nothing here has been applied by the agent; no `terraform apply` was run):
1. **Create the secret locally** and keep it out of chat/logs: `openssl rand -base64 48` (64 chars). Paste it into GitHub → Settings → Secrets and variables → Actions → **Secrets** → `AUTH_PHONE_SECRET` (or pipe it: `openssl rand -base64 48 | gh secret set AUTH_PHONE_SECRET`). Do not commit it or put it in a variable. It ends up (a) in the HCP Terraform state (encrypted) and (b) as a Render environment variable — treat DEV as the only place it is valid; rotating it logs everyone out. Never reuse it for production.
2. Add GitHub **variables** `AUTH_PHONE_ENABLED=true` and `AUTH_DEV_OTP_ENABLED=true` (allowlist default `+77000000001,+77000000002,+77000000003`; override with `TF_VAR_auth_dev_otp_allowed_phones`).
3. Run *Terraform DEV* (plan only) and review it. Expected: Render service `kunde-backend` **replaced** (1 destroy + 1 create; Neon and the contract are untouched) because provider 1.9.1 cannot update free services in place (issue #80). `KUNDE_ENVIRONMENT=dev`, `AUTH_PHONE_ENABLED`, `AUTH_PHONE_SECRET`, `AUTH_DEV_OTP_*`, `CONSUMER_IDENTITY_ENABLED=true` are set. **The replacement gets a new slug and URL** (`backend_url` output); the old `kunde-backend-5wwg` URL stops working.
4. Apply with `replace_render=true`, `apply=true`, `confirm=apply-dev` only after you approve the plan. Wait for the cold start (~1 min); Flyway applies V9.
5. Run *Android Release APK (DEV)* with `api-base-url` = the **new** URL + `/api/v1/` and install; sign in with `+7 700 000 00 01` and code `123456`.

Local: `AUTH_PHONE_ENABLED=true AUTH_PHONE_SECRET=<32+ chars> AUTH_DEV_OTP_ENABLED=true AUTH_DEV_OTP_ALLOWED_PHONES=+77000000001 KUNDE_ENVIRONMENT=local CONSUMER_IDENTITY_ENABLED=true`, then `mvn spring-boot:run`.

## Evidence and limits

Backend: `PhoneNumberTest`, `PhoneAuthGuardTest`, `DevOtpProductionStartupTest` (real application refuses DEV OTP in production), `PhoneAuthHttpIntegrationTest` (PostgreSQL: full login → profile → consents → addresses, refresh rotation/replay, logout, OTP expiry, lockout, throttling, no enumeration, forged/expired/wrong-audience tokens, no secrets in logs/DB). Flutter: gateway and widget tests incl. restore, logout, errors. These are build/fixture tests: no physical-device run, no real SMS/WhatsApp, no live provider.

## Production gates (open)

Independent security review; approved OTP channel and price (D-11); privacy/residency approval for stored phones and OTP processors (TASK-007, D-08); asymmetric signing or managed key rotation; distributed rate limiting and edge protection (current limits are per instance / per number); account recovery and phone-number-change policy; SIM-swap risk acceptance; deployment check proving DEV OTP is off in production.
