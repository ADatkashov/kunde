# Proposed logical data model

No migration is part of this EP-002 stage. Names are illustrative and should follow current schema ownership and naming conventions. Existing migration creates domain schemas but no user identity tables; architecture notes reserve IAM/identity ownership for a later approved change.

| Entity | Essential fields / constraints | Owner and purpose |
|---|---|---|
| `kunde_user` | `user_id UUID PK`, `status`, `created_at`, `updated_at`, `deleted_at?`, `locale?`; no phone primary key | Identity domain; permanent internal principal. |
| `external_identity` | `identity_id`, `user_id FK`, exact `issuer`, exact `subject`, `linked_at`, `last_seen_at`; unique `(issuer,subject)` | Maps external IdP to KUNDE identity. No credential secret. |
| `contact_method` | `contact_id`, `user_id`, `kind`, `value_ciphertext` or approved encrypted representation, `value_search_hash` if justified, `verified_at`, `revoked_at`, `is_primary` | Phone/email and proof history. Unique policy is an explicit decision due shared/recycled contacts. |
| `auth_session_ref` | Opaque KUNDE session ID, user, provider session handle/reference, device label, created/last seen/revoked times | Optional minimal session inventory/revoke bridge; no raw token. Provider remains session authority. |
| `identity_link_event` | actor, target user, old/new identity refs, operation, result, timestamp, correlation, proof class | Auditable identity link/unlink/migration. Restricted access. |
| `consent_record` | user, purpose, notice version, locale, granted/withdrawn time, source | Product/privacy consent, separate from OTP verification. |
| `security_event` | event type, actor/target references, outcome, risk summary, timestamp, correlation | Security audit; minimize PII/token material; retention/access policy required. |
| `business_membership` (domain-owned) | principal, tenant/business, role/grant, scope, validity, grantor, status | Partner/provider authority; not owned by IdP and not embedded as permanent token truth. |

## Data rules

- Random UUID IDs are non-reusable; no sequential or phone-derived identity.
- Persist OIDC `(iss,sub)` exactly after issuer validation. Index for lookup; never normalize subject case.
- Store contact values only when necessary, encrypted at rest with key separation; masked values for UI. Hashing phone alone is not anonymization because phone search space is enumerable; if a lookup hash is justified, use keyed HMAC and protect/rotate key.
- Do not persist raw OTP, access token, refresh token, authorization code or provider API secret.
- Apply foreign keys and uniqueness only after product rules for shared/recycled contact, multiple identity providers and account merge are settled.
- Residency applies to database, replicas, backups, logs, analytics exports and support tooling; see privacy document.
