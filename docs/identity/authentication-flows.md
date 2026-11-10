# Authentication flows

## Consumer registration and login (proposed)

1. User enters phone in the branded KUNDE auth experience hosted by the selected IdP (or its supported extension); app starts Authorization Code + PKCE in the OS browser and creates random `state`, `nonce`, verifier/challenge.
2. IdP applies generic response, anti-enumeration, phone normalization, per-phone/IP/device controls and issues a challenge. KUNDE's approved SMS adapter sends the IdP-generated message; challenge lifetime and code validation remain IdP-owned.
3. User enters code; IdP verifies it, creates or authenticates provider subject and returns authorization code to the exact app link.
4. Flutter verifies state/nonce/issuer/redirect and exchanges code with verifier. It stores refresh token in OS-protected storage and keeps access token in memory where practical.
5. API validates access token's signature, exact issuer, audience, time and client policy; resolves `(iss, sub)` to KUNDE user ID; checks resource-level permissions.

If a finalist cannot safely provide phone-first login in this flow, build and threat-test a supported IdP extension. Do not move token issuance into an ad hoc Spring endpoint.

## Step-up and sensitive changes

Phone/email change, linking/unlinking, account deletion, payment credentials and privileged/admin actions require recent reauthentication (`auth_time`/`max_age`), verified new channel and required assurance (`acr`/`amr`). For admin, require phishing-resistant WebAuthn/passkey or hardware-backed factor where supported; SMS alone is unacceptable. Sensitive changes notify the old verified channel and create audit records.

## Recovery

Offer another previously registered factor or a controlled support recovery. Phone number possession alone must not recover all factors or merge accounts. Staff cannot see or set codes. Recovery uses generic responses, proof review, delays/risk checks where justified, notifications and revocation of sessions. Preserve an accessible support path.

## Cross-app SSO

Separate OIDC clients for Consumer, Partner, Provider and Admin. Browser SSO can reduce prompts on the same device; native apps must not share refresh-token files. A user may sign in independently on each app, while KUNDE resolves all approved client subjects to the same internal identity. App role context is selected after login and validated against server grants.

## Standards

Use native Authorization Code + PKCE with an external user-agent as specified by [RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252); apply current OAuth security guidance in [RFC 9700](https://datatracker.ietf.org/doc/html/rfc9700). No implicit, password grant, embedded WebView, wildcard redirects or native client secrets.
