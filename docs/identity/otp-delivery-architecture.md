# OTP delivery architecture

## Ownership boundary

IdP generates, stores/verifies and consumes OTP challenges; KUNDE's `OtpDeliveryPort` transports the IdP-authored message through a provider adapter. Adapter response means only “provider accepted / delivered / failed”, not “identity verified”. If a provider only exposes its own generate-and-verify API, integrating it requires a supported IdP authenticator extension and explicit lock-in/security review. Do not invent a custom token-exchange endpoint in Spring.

## Logical path

`IdP challenge → notification contract → policy router → SmsProviderPort → Mobizon/SMSC adapter → delivery status callback/poll → redacted event`. Provider secrets stay server-side in a secret manager; network egress allowlisted where feasible. Use HTTPS, request signing/auth, timeouts, per-provider circuit breaker, bounded retries with jitter, idempotency/correlation key and separate attempt ID. Validate callbacks and replay protection.

## Initial policy defaults for POC

- 6-digit random code; 5-minute expiry; max 5 verification attempts; 30–60 second resend cooldown.
- Per-phone, IP, device/install and global limits; progressive friction/captcha only where supported and accessible; deny/slow suspicious SMS pumping.
- Generic public response regardless of existing account. Never log/store plaintext OTP in KUNDE; IdP must document hashing/one-time consumption. Correlate only challenge ID and provider message ID.
- Limit retries to a small bounded count and never replay a provider request blindly when acceptance is ambiguous. Query status or create a new explicit attempt.

These values are starting risk/UX hypotheses. Tune in controlled tests and confirm provider/IdP capabilities; they are not legal or vendor defaults.

## Cost, privacy and fallback

Track counts, outcome, latency buckets, route, country code and billable segment count; use aggregates, short retention, role-restricted access and no full phone in generic observability. Apply spend cap/alerts and anomaly kill switch. Fallback channel must be consented, commercially approved and separately threat assessed. WhatsApp/Telegram should not receive an OTP as automatic fallback absent valid user opt-in, approved templates, supported onboarding and a comparable account-security policy. SMS outage never means bypassing verification.

## Resilience

On provider timeout, mark attempt indeterminate and reconcile; on hard failure offer allowed retry or wait. Circuit-break provider, retain IdP challenge only until expiry, and surface generic localized status. Provider callbacks must not be able to authenticate a user. Dead-letter only redacted metadata. Operator outages need runbook and support notice.
