# ADR-015: Portable KUNDE identity (amended 2026-11-14: own phone-OTP authentication)

- **Status:** ACCEPTED for synthetic DEV implementation. Production readiness remains gated.
- **Date:** 2026-11-10; **amended 2026-11-14** (owner decision, see [Amendment](#amendment-2026-11-14-own-phone-otp-authentication-supersedes-the-oidc-provider)). Sections below the amendment are retained as history.
- **Related:** ADR-009 (provider TBD), ADR-013 (fail-closed security boundary), EP-002, PRD AUTH-001/AUTH-002.

## Context

KUNDE needs authentication for Consumer, Partner, Provider and Admin surfaces, phone-first onboarding in Kazakhstan, session/recovery controls, and an identity that survives an IdP change. Current backend has an OIDC/JWT resource-server boundary, but no account lifecycle, identity mapping schema, token issuer or mobile session implementation. Kazakhstan personal-data storage/transfer constraints and KZ OTP cost/coverage are material. No provider, region, quote or contract has been approved.

## Proposed decision

1. KUNDE owns a permanent opaque UUID user key and maps verified external `(issuer, subject)` identities to it. Business data and permissions never use phone/email or IdP subject as primary key.
2. Use an OIDC/OAuth provider for authentication and tokens; native Flutter clients use Authorization Code + PKCE in the system browser. KUNDE Spring API remains a fail-closed resource server with exact issuer and audience validation.
3. KUNDE domain owns business authorization, lifecycle restrictions and resource-level grants. IdP claims supply authentication context and coarse scopes only.
4. Separate IdP responsibility from OTP transport. Prefer IdP-generated/verified challenge with replaceable, server-side SMS adapter; integrate a vendor-specific OTP verifier only through a supported IdP extension and after a lock-in/security review.
5. Run Keycloak and ZITADEL as leading POC candidates. Treat ZITADEL or Auth0 managed service as operational alternatives only if Kazakhstan data location, contract, current cost and export pass hard gates. This ADR does not select a vendor.

## Alternatives considered

- Bespoke Spring authentication/token issuance: rejected for protocol and account-security risk; revisitable only with a formally staffed identity platform team and independent security review.
- Direct Firebase-centric authentication: not preferred because Firebase ID-token/client model increases coupling; still valid if the product deliberately accepts that architecture and demonstrates audience/region suitability.
- Cognito: viable if AWS region/service, local SMS routes, storage obligations and cost are proven; not selected by ecosystem assumption alone.
- Managed Auth0: viable if region/contract and volume economics are verified; public plan page is insufficient for KUNDE total cost.
- Single vendor for IdP and OTP: rejected as default because it couples authentication state, delivery and KZ message pricing; allowed only when technical fit demonstrably outweighs migration and outage costs.

## Consequences

- Positive: KUNDE business identity survives IdP migration; Spring remains standards-based; privileges stay in domain; OTP channel can be replaced.
- Negative: KUNDE must build and operate mapping, lifecycle, authorization checks, audit, migrations and support recovery; custom phone-first IdP UX may need extension code.
- Operational: managed deployment lowers infrastructure burden but does not remove residency/processor review. Self-host improves data control only if every database, log, backup, telemetry copy and support workflow is placed and operated appropriately.
- Security: SMS is a possession signal with SIM-swap/recycling risk; admin requires stronger MFA; JWT revocation can be delayed until expiry unless online/session checks are added.

## Decision gates before acceptance

- Written legal/privacy approval for data location, cross-border processing, retention, notices/consent and vendors under current Kazakhstan law.
- Comparable written price/feature/SLA/export/subprocessor answers for 1k–1m MAU and transactional OTP routes.
- POC of phone-first UX, IdP-owned challenge, Flutter PKCE callback, Spring issuer/audience validation, refresh rotation/revocation, export and provider outage handling.
- Named operations owner accepts patching/HA/backup/DR/on-call if self-hosted; product/security accept recovery and SIM-swap residual risk.

## Revisit

After POC and procurement/legal evidence, before real user data, production issuer configuration or migrations. If hard gates fail, re-score options and issue a superseding ADR. Keep ADR-009 proposed until this decision is accepted.

## Local POC evidence (2026-11-10, recovery 3.0)

Java 21/Maven 3.9.9 used the local ignored truststore from `docs/identity/poc/Initialize-MavenTrust.ps1`; Windows validates the chain before root import and JSSE certificate/hostname checks stay enabled. Previously completed Spring Boot 3.5.7 `mvn verify`: 21 tests passed, 0 failures/errors/skips. Fixture tests cover resource-server security and JWKS behavior; they are not provider-issued token evidence.

Keycloak 26.8.2 positive E2E **passed** on Pixel 9 Pro AVD: Android Chrome Custom Tab displayed login; synthetic user completed Authorization Code + PKCE; Flutter received callback and exchanged the code; Spring validated the real access JWT's signature, issuer, `kunde-api` audience, expiry and `kunde.poc` scope; protected API returned HTTP 200. Refresh completed and the API again returned 200. After Flutter local token clearing/provider logout request, a new authorization presented the login form rather than silently reusing the prior browser session. Full flow, screenshots and limits are in [`docs/identity/poc/end-to-end-evidence.md`](../../identity/poc/end-to-end-evidence.md).

Recovery causes: A persisted Keycloak realm was not overwritten by import, so the live client lacked optional `offline_access`; correcting its scopes fixed `invalid scopes`. Chrome first-run/ANR overlays accounted for apparent blank loading. The first accepted API request exposed a missing `sub` claim and null-intolerant POC response map; assigning the standard Keycloak `basic` Subject mapper resolved it without relaxing issuer/audience validation. Android networking now uses `adb reverse` to preserve the exact localhost issuer; see `android-networking.md` and `pkce-debugging.md`.

ZITADEL 4.19.5 recovery startup completed in 96.1s, all four services reported healthy, and discovery exposed consistent localhost issuer/auth/token/JWKS/end-session endpoints. Its project/native app/test user were not configured; no Android or token/API flow was performed. This is incomplete setup, not a failed authentication result. Live negative JWT cases, refresh replay/revocation, access JWT behavior after logout, session expiry, and equivalent ZITADEL flow remain outstanding.

**POC conclusion:** Keycloak is the evidence-backed front-runner for continued integration, but comparison is incomplete and does not justify provider approval. ADR-015 remains **PROPOSED**. TASK-005 stays pending explicit owner approval; TASK-006 is not complete and production readiness is not established.

## Final bounded evaluation 4.0 (2026-11-10)

Recommend self-hosted Keycloak for owner review. The [4.0 decision report](../../identity/poc/final-provider-decision-report.md) and [weighted matrix](../../identity/provider-decision-matrix.md#40-evidence-adjusted-self-hosted-finalists) supersede the historical comparison above. ZITADEL's local Native client issues JWT access tokens. Its signed project and organization role semantics require a POC-specific authorization mapping. Keep the portable OIDC boundary and explicit owner, privacy/legal, commercial and operations gates. ADR-015 is **PROPOSED**.

## Keycloak security hardening 1.0

The [readiness package](../../identity/keycloak-readiness/README.md) records live browser logout and targeted session deletion. Both rejected online refresh immediately while Spring accepted the existing JWT until approximately `exp + 60 s`. The drill rejected refresh replay and accepted the new signing key without restarting Spring, then verified retirement of the old public key after expiry. The proposed policy combines online rotation, bounded access lifetime and clock tolerance, and KUNDE-owned restricted-account enforcement for actions requiring a faster revoke SLO. [Operational gates](../../identity/keycloak-readiness/production-readiness.md) and owner review remain open. ADR-015 stays **PROPOSED**.

## Owner approval and implementation decision, 2026-11-11

The project owner explicitly approved self-hosted Keycloak as primary IdP and ZITADEL as architectural fallback in the EP-002 Identity & Access Implementation 1.0 instruction. This approval supersedes the pending provider-selection statements in historical evaluation sections above.

Use OIDC Authorization Code + PKCE through the system browser. Persist an immutable KUNDE UUID and bind verified issuer/subject pairs uniquely. Never automatically link accounts by matching email or phone.

The development token policy is 300-second access tokens, refresh rotation with Max Reuse 0, 1800-second session idle and 43200-second maximum session. Verify actual runtime configuration and behavior before recording a pass. The earlier readiness drill measured approximately 60 seconds of JWT expiration tolerance. Implementation must document its configured tolerance and resulting acceptance window.

Technical evidence is preserved in the final provider evaluation and Keycloak readiness package. Earlier results establish POC feasibility and are historical evidence only. Keycloak operations require patching, backups and restore rehearsal, signing-key rotation, availability planning, monitoring and named operations ownership. Privacy/legal, data location, OTP, recovery, abuse controls and production security gates remain open. Architecture approval authorizes development with synthetic users. Production rollout requires separate evidence and approval.

## Amendment 2026-11-14: own phone-OTP authentication supersedes the OIDC provider

**Decision (Product Owner, 2026-11-14).** KUNDE does not adopt Keycloak, ZITADEL or any external OIDC provider. Authentication is implemented in the Spring Boot monolith: phone number + one-time code, short-lived access JWT, rotating refresh token, PostgreSQL storage. This supersedes decision points 2, 4 and 5 and the owner approval of 2026-11-11 (Keycloak primary / ZITADEL fallback). The "Bespoke Spring authentication" alternative, rejected above, is now the chosen option; its original rejection condition ("a formally staffed identity platform team and independent security review") is **not** met and becomes a production gate (below).

**Why.**
- DEV needs a working login on a phone now. No IdP is deployed, and the free Render/Neon footprint cannot host Keycloak (memory, cold start, a second database) without paid services.
- The product is phone-first and the OTP channel (SMS/WhatsApp, D-11) is not selected. A custom flow lets DEV use a clearly fenced test code and lets production plug a real channel in behind one interface.
- The system-browser/AppAuth hop and IdP theming added UX and operational surface that the first user cohort does not need.

**What stays.** Point 1 (permanent opaque KUNDE UUID; `identity.users`, `identity.external_bindings(issuer, subject)`; never phone/email as business key), point 3 (domain owns business authorization), the fail-closed OIDC resource-server boundary of ADR-013 (the API still validates signature, exact issuer, audience, time claims and the existing `ConsumerAccessPolicy`), and the production gates (privacy/residency, OTP vendor, operations, recovery). The `(issuer, subject)` binding is kept so a future IdP can be reintroduced without changing business data: the own issuer is `kunde-phone-auth` and the subject is the KUNDE user UUID.

**What changes.**
- `POST /api/v1/auth/otp/request`, `/auth/otp/verify`, `/auth/token/refresh`, `/auth/logout` (feature flag `AUTH_PHONE_ENABLED`, off by default; mutually exclusive with `OIDC_ISSUER_URI`).
- Delivery sits behind `OtpDeliveryProvider`; `DevOtpProvider` is the only implementation wired. `SmsOtpProvider` and `WhatsAppOtpProvider` are unusable placeholders until D-11.
- DEV OTP (`123456`) works only with `AUTH_DEV_OTP_ENABLED=true`, `KUNDE_ENVIRONMENT` in dev/local/test, no `prod`/`production` profile and an allowlist of synthetic `+7700000XXXX` numbers. Any other combination aborts startup (`PhoneAuthGuard`).
- Flutter uses a phone/OTP screen instead of AppAuth when built with `PHONE_AUTH_ENABLED=true`. The AppAuth/OIDC code remains in the tree, unused by DEV builds, until the owner decides to delete it.

**Consequences.**
- KUNDE now owns OTP abuse protection, token lifetime/rotation/revocation, key management and account recovery. Details and controls: [phone-otp-auth.md](../../identity/phone-otp-auth.md).
- Access tokens are HS256 with a single shared secret (`AUTH_PHONE_SECRET`); there is no JWKS, key rotation is a manual secret change that invalidates all sessions. Acceptable for DEV; production needs a key-management decision.
- A server-side session check on every authenticated request makes logout/replay revocation immediate, at the cost of one indexed lookup.
- Per-IP limiting behind Render's proxy is coarse (`forward-headers-strategy: none`); the per-phone limits are the effective control.
- SIM-swap/recycled-number risk, account recovery, support-assisted changes, and phone data (stored as E.164) are unresolved for real users.

**Production gates added by this amendment (all open).** Independent security review of the auth implementation; approved SMS/WhatsApp channel and cost (D-11); Kazakhstan privacy/residency approval for stored phone numbers and OTP processors (TASK-007/D-08); asymmetric signing or managed key rotation; shared (distributed) rate limiting and edge abuse protection; account recovery and number-change policy; DEV OTP verified absent from production configuration by a deployment check. ADR-015 status for production stays gated; no vendor is approved by this amendment.
