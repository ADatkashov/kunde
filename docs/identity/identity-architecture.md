# Identity architecture

## Context and current foundation

KUNDE has Consumer, Partner, Driver/Provider and Admin surfaces, initially launching in Almaty. Backend foundations are Java 21, Spring Boot 3.5.7, Spring Security, PostgreSQL and Flyway. The security boundary accepts OIDC JWTs only when issuer configuration is present and validates issuer/audience; missing issuer fails closed. This is a resource-server foundation, not user registration, sessions, token issuance or account recovery. Existing migrations have no user identity tables. Flutter currently has a shell/capability-check foundation, not an auth client or token vault. ADR-009 keeps OIDC/OAuth and provider choice open; ADR-013 establishes a reversible security boundary. Preserve both.

## Proposed architecture

1. A standards-based external Identity Provider (IdP) authenticates users and issues OIDC tokens. Prefer managed service only if Kazakhstan data location and contract are acceptable; otherwise operate a self-hosted IdP in an approved Kazakhstan environment.
2. KUNDE Identity domain owns an immutable opaque `kunde_user_id`, external identity mappings, verified contact proofs, lifecycle, consent references, and security-event references. It does not copy IdP passwords or raw OTPs.
3. KUNDE API resolves `(iss, sub)` to `kunde_user_id`, validates tokens, then evaluates KUNDE-owned resource permissions in domain services.
4. A replaceable `OtpDeliveryPort` sends IdP-generated messages through approved SMS/WhatsApp adapters. The adapter never decides whether a user is authenticated.
5. Separate OIDC clients for each KUNDE app and environment. Admin gets a distinct client, strong policy and audit path. APIs accept only their configured audiences.

### Trust boundaries

- Flutter ↔ IdP: public native OIDC client, external user-agent, Authorization Code + PKCE, exact registered redirects, state and nonce.
- Flutter ↔ KUNDE API: TLS bearer access token for the API audience; no ID token as API credential.
- KUNDE API ↔ IdP metadata/JWKS: outbound TLS, pinned configured issuer, bounded cache and controlled key refresh.
- IdP ↔ OTP adapter ↔ telecom/channel: credentials held server-side, no PII in generic logs, provider response correlated by opaque attempt ID.
- KUNDE database ↔ KUNDE business modules: internal user ID and explicit tenant/resource grant; never authorize only from a phone or unvalidated JWT claim.

## Architecture choice

Conditional preference: **hybrid boundary, self-host-capable OIDC IdP with vendor-neutral SMS**. Evaluate Keycloak as the first self-hosted candidate and ZITADEL as a credible alternative; do not select before testing custom phone-first UX, current supported OTP delivery extension, operating effort, Kazakhstan storage of every personal-data copy, and failure recovery. Auth0 is the managed fallback only if its contract/region fit. Cognito and Firebase remain comparator options with stronger ecosystem coupling. Details and scores are in the companion documents.

## KUNDE identity portability

The IdP subject is an external credential identifier, not the KUNDE user ID. A migration imports users into a new IdP, verifies account control, writes a new `(issuer, sub)` link to the existing `kunde_user_id`, and preserves orders, ledger and memberships. Never key business records by phone, email or IdP subject. Avoid syncing business roles to IdP as the source of truth.

## Operational invariants

- Issuer and audience validation fail closed. JWT signature, `iss`, `aud`, `exp`, `nbf` are required; acceptable algorithm/key policy is configured, not token-controlled.
- Access tokens are short-lived; public-client refresh tokens rotate or use sender constraint. Refresh reuse revokes the token family and raises a security event.
- Authentication proves an account; authorization checks the requested action on the specific resource on every request.
- Provider failure never falls back to trusting an unverified OTP, stale authorization claim, or alternate issuer.
- User account deletion, legal retention, backups, logs and analytics each have explicit data-lifecycle rules.

## Sources and status

Native app flow follows [RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252) and OAuth threat mitigations follow [RFC 9700](https://datatracker.ietf.org/doc/html/rfc9700). The current KUNDE implementation facts above are repository inspection; no authentication behavior was changed in this EP-002 design task. This document is a proposal, not a deployment decision.
