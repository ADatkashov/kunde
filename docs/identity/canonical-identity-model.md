# Canonical identity model

## Stable key

Generate a random opaque KUNDE UUID (UUIDv4 is the conservative proposal) at first account creation. The UUID is stable across apps and IdP migration, contains no phone/email/tenant, and is never recycled. No user table currently exists; this is a logical design only.

## External mapping

Map exact OIDC `(issuer, subject)` to one KUNDE UUID. Treat `iss` as the configured canonical issuer URL and `sub` as opaque, case-sensitive data. Unique constraint: `(issuer, subject)`; index `kunde_user_id`. A changed subject requires a verified migration/link operation, never a lookup by phone alone. Tokens from any other issuer/audience are rejected.

## Contacts and proof

Phone and email are contact methods with canonical value, type, verification status, proof time, source, and optional validity interval. Normalize phones to E.164 and validate the allocated country/number range; normalize email conservatively and preserve display value. Do not assume phone or email is globally unique forever: recycled SIMs and shared family/business contacts are expected. Define product policy for duplicate verified contacts, account recovery, and contact reassignment before enforcing a unique constraint.

## Linking and migration

Link requires a fresh authenticated session for the current account and proof of control of the new identity. If the new identity maps elsewhere, deny automatic merge; require both-account proof or staffed recovery with audit and cooling-off policy. Never auto-link on matching email/phone claims alone. Migration writes a second issuer/subject mapping to the existing KUNDE UUID after proof, then expires old provider sessions and retains a reversible audit event.

## Account types

One natural person can be consumer and separately hold membership in a partner business or provider organization. Authentication account is not a role. Business ownership, staff membership, driver/provider approval and admin assignment are separate domain grants. Admin enrollment is invite-only and never inferred from consumer registration. Family accounts/shared contact numbers require an explicit future model, not duplicate-user guesswork.

## Claims boundary

Resolve `iss + sub` server-side. `email`, `phone_number`, `phone_number_verified`, display name and locale are attributes, not stable primary keys or permissions. `azp`/client and audience constrain intended use. KUNDE should minimize claims copied into its own profile and refresh claim freshness for high-risk actions.
