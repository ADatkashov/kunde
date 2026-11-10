# Authorization model

## Rules

Authentication identifies a principal; authorization decides whether it can perform an action on a resource. KUNDE backend is the source of truth for business grants. Deny by default and check at the API/service boundary for every request. Client-hidden UI is not a control.

## Initial principal classes

- Consumer: own profile and own permitted orders/support cases.
- Partner owner/staff: only assigned business and branch resources; scope and permissions derive from active membership.
- Provider/driver: only assigned tasks, availability and own permitted profile.
- Support: narrow case/customer views with reason, limited PII and audit.
- Finance: reconciliation and refund capabilities separated by approval threshold.
- Admin: invite-only privileged identity, strong MFA, just-in-time/time-bound elevation, audited reason and least privilege.

Names are proposals; do not create all future permissions in EP-002.

## Minimal permission shape

Represent grants as `(principal_id, application, role, resource_type, resource_id/tenant, permission_set, valid_from, valid_until, status, grantor)`. A request evaluates action + resource + active membership + account state + any approval/risk condition. A partner does not inherit admin permissions; a provider does not gain access to another provider's assigned task. Explicitly model owner transfers and revoke staff membership promptly.

## Token claims

Token claims may identify issuer, subject, client, audience, authentication time, assurance and coarse scopes. Avoid embedding the full dynamic permission graph in long-lived tokens. App-supplied `tenant_id`, `business_id`, account type, `role`, or resource ID is an untrusted selector; server verifies membership on each operation. Never authorize a broad role solely from client-side route or phone verification.

## Admin boundary

Admin has separate OIDC client, redirect allowlist, assurance policy, short token/session lifetime, mandatory MFA, just-in-time elevation for high-risk permissions, immutable audit events and periodic access review. No public registration path can request or grant admin. Break-glass is separately provisioned, time-bound, monitored and tested; no silent shared admin account.
