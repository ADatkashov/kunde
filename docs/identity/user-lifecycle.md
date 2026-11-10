# User lifecycle

| State | Entry / transition | Required controls |
|---|---|---|
| `pending_verification` | First registration started | Generic response, challenge TTL, anti-abuse limits; no active KUNDE account yet. |
| `active` | IdP confirms required contact and KUNDE mapping is created | Opaque UUID; consent/version references captured where needed; least-privilege consumer baseline. |
| `restricted` | Risk, legal, support or domain policy restricts access | Restriction reason and scope stored in KUNDE; API enforces on every request; user-facing explanation avoids sensitive detection detail. |
| `suspended` | Confirmed abuse/security/legal action | Revoke IdP sessions/refresh tokens; block access promptly; preserve evidence and appeal process. |
| `deletion_pending` | Authenticated, fresh request | Confirm reauthentication; explain financial/contractual retention separately; revoke sessions and prevent new activity. |
| `deleted_or_pseudonymized` | Retention obligations satisfied | Remove or irreversibly pseudonymize eligible PII; retain only lawful minimum; preserve non-identifying financial records per approved policy. |

## Contact and identity sub-states

Each phone/email is `unverified`, `verified`, `revoked` or `expired`. Verified means proof at a point in time, not permanent proof of current ownership. Changing a phone requires proof of old account plus new number, fresh auth and notification to the former contact where possible. Reassigned numbers create a recovery risk; do not transfer existing order or wallet history to a new claimant based on number reuse.

## Sessions and credentials

IdP owns credential reset, token families, login sessions and revocation. KUNDE mirrors minimal session metadata only if needed for device list and revocation UX, using IdP session handle or opaque mapping. Device labels are untrusted user-supplied display metadata. Account deletion and suspension invoke provider revocation and verify completion; retry with an outbox/work item and alert when unavailable.

## Consent and audit

Store consent purpose, notice version, timestamp, locale and withdrawal separately from authentication proof. Security audit events record actor, action, target, outcome, correlation, time and source class; avoid OTP, bearer token, full phone, recovery answer, or sensitive payload. Retention and access roles are approved by privacy counsel.
