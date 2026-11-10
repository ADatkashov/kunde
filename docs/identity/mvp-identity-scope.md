# EP-002 implementation MVP boundary

This is a proposed next-stage scope, not implementation authorized by this design document.

## Include in first implementation increment

- One approved OIDC issuer with dev/staging/prod isolation and separate clients for Consumer, Partner, Provider and Admin surfaces as applicable.
- Consumer phone-first registration/login through IdP-owned OTP, generic responses, anti-abuse/rate controls, account mapping to stable KUNDE UUID.
- Standard Authorization Code + PKCE in Flutter system browser, secure refresh storage, logout and expiry handling.
- Spring resource-server validation of issuer/audience/key/time; fail-closed identity mapping and current-user endpoint.
- Minimal active/suspended/deletion-pending lifecycle, security audit and support recovery procedure.
- Resource-based authorization foundations; consumer self-resource access and explicit tenant membership checks for any partner/provider feature enabled.
- Phone change and session listing/revocation only if selected IdP capabilities and KUNDE API contract support secure proof/revocation.
- OTP delivery adapter behind interface, initially one contracted route, cost/abuse dashboards and operational runbook.

## Exclude until separately prioritized

Social sign-in, password authentication, family/shared accounts, multiple simultaneous IdPs, automatic identity merge, full admin portal, complex delegated support/finance workflows, WhatsApp/Telegram fallback, custom KUNDE OTP/token issuer, global active-active identity, passwordless passkeys for all users, custom consent management UI, account migration automation.

Admin accounts must not use consumer SMS-only MVP policy: require invite-only provisioning and strong MFA before any privileged production access.

## Acceptance evidence for implementation

1. Positive/negative auth tests for issuer, audience, expiry, signature, unknown subject and suspended user.
2. PKCE callback and state/nonce tests on supported iOS/Android versions; secure storage inspection and logout/reuse tests.
3. OTP abuse, enumeration, retry, timeout, spend-cap and status-reconciliation tests in sandbox/test numbers.
4. Tenant/resource authorization negative tests; no consumer-to-partner/admin privilege inheritance.
5. Data-flow, location, backup, log-redaction and retention evidence approved by counsel/owner.
6. Provider outage, restore, key rotation and identity-provider migration rehearsal.
