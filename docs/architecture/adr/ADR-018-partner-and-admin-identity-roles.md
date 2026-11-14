# ADR-018: Partner and Admin identity roles on the own phone-OTP authentication (D-14)

- **Status:** PROPOSED — awaits Product Owner approval (D-14 owners: Finance + Security). No code, schema or token change in this ADR's PR. No Keycloak, ZITADEL or other external IdP is introduced.
- **Date:** 2026-11-14
- **Related:** ADR-015 (own phone-OTP, amended 2026-11-14), ADR-013 (fail-closed boundary), ADR-014 (catalog stays empty), PRD 1.1 §23 D-07 (approved roles) and D-14 (open), [authorization model](../../identity/authorization-model.md), V8 `marketplace.partner*`.

## Context

Phone-OTP already issues an access JWT; `ConsumerAccessPolicy` requires scope `kunde.consumer`. D-07 approved partner roles (Owner/Manager/Operator) and a KUNDE Administrator with manual verification, and required "existing identity boundaries, no second identity architecture without an approved ADR". Partner persistence (V8) and the offering↔partner link (V10) exist, but there is no HTTP API for partners or admins because the identity side was undecided. D-14 (admin separation of duties, approval thresholds) is open. Admin identity must never be reachable by public registration.

## Proposed decision

1. **One identity, three audiences.** Keep the single `identity.users` account and the existing token issuer. The access token carries coarse scope only: `kunde.consumer` (every OTP-verified user), `kunde.partner`, `kunde.admin`. Scopes are authorization *entry gates*, not grants; business permissions are never embedded in the token (authorization model).
2. **Scopes are derived server-side at token issue/refresh from database state, never from the client:**
   - `kunde.partner` only if the user has at least one ACTIVE `marketplace.partner_staff` row.
   - `kunde.admin` only if the user has an ACTIVE row in a new `identity.admin_grants` table (columns: user, permission set, granted_by, granted_at, revoked_at). Rows are created **out of band** (migration-free operator procedure by the owner, later an admin-invites-admin flow with dual control per D-14). No public endpoint, OTP login, onboarding request or profile field can create or elevate to admin.
   - Revocation takes effect at the next refresh; every partner/admin request additionally re-checks membership/grant in the database (short token lifetime is not the only control).
3. **Partner onboarding.** Any authenticated consumer may submit a partner application: creates `marketplace.partners` (`PENDING_REVIEW`) plus a verification `SUBMIT` event and an OWNER `partner_staff` row, using the existing `PartnerService` rules. The application grants no public visibility; `mayProcessOrders`/catalog visibility still require `APPROVED` (ADR-014 gates unchanged).
4. **Partner approval is admin-only.** Transitions `PENDING_REVIEW → APPROVED|REJECTED|INFO_REQUESTED|LIMITED|SUSPENDED` are executed by `kunde.admin` + an admin grant covering partner verification, with a mandatory reason, written to `partner_verification_events` (append-only). An admin cannot approve a partner they are staff of. Real KYC documents are out of scope (no provider approved, D-07 gates).
5. **Isolation and IDOR.** Partner endpoints never trust a client-supplied partner id alone: the partner is resolved from the caller's ACTIVE membership; a path `partnerId`/offering id outside that membership returns the same 404 as an unknown id. Role checks: OWNER and MANAGER manage profile/offerings; OPERATOR is read-only on offerings (orders later); only OWNER manages staff. Every query is parameterized by the resolved partner id (`where partner_id = ?`), covered by negative cross-partner tests.
6. **Offerings.** A partner creates/edits its own offerings as `DRAFT` (names RU/KK required, KZT price in tiyn, availability). `PUBLISHED` requires: partner `APPROVED`, price set (DB check V11) and name completeness; suspension/loss of approval hides the offering without mutating it (already implemented in the consumer read model). Nothing is auto-published; no demo partners or offerings are seeded.
7. **Audit.** Partner/admin writes append to events tables (who, what, before/after status, reason, time, correlation id); no PII beyond user ids in events; audit rows are append-only (no update/delete grants, tests).
8. **Admin hardening (production gate, not DEV).** Phone-OTP alone is insufficient for production admin: before any real admin use require a second factor/step-up, short sessions and dual control for high-risk actions (refund thresholds, admin grants). In synthetic DEV, admin is limited to owner-provisioned synthetic accounts.

## Alternatives considered

- *Separate partner/admin identity pool or external IdP:* rejected (owner: no Keycloak/ZITADEL; D-07 forbids a second identity architecture).
- *Permissions inside the JWT:* rejected (stale grants, token bloat; authorization model says avoid).
- *Self-serve admin via invite code in the app:* rejected — a public path to admin.

## Consequences

- Positive: reuses existing issuer and V8 tables; small surface; deny-by-default; revocation is immediate on server re-check.
- Negative: new migration (admin grants), new token claim logic and ~3 controllers; admin hardening is deferred and keeps admin DEV-only.

## Implementation plan (after approval)

1. V12 `identity.admin_grants` + scope derivation in `AccessTokenIssuer` + tests (consumer never gets partner/admin scope; revoked staff loses scope).
2. `POST /api/v1/partner/applications`, `GET/PATCH /api/v1/partner/profile` (OWNER/MANAGER).
3. `GET/POST/PATCH /api/v1/partner/offerings`, publish/unpublish; IDOR and role tests.
4. `GET /api/v1/admin/partners?status=`, `POST /api/v1/admin/partners/{id}/decision` with reason; admin-cannot-approve-own test.
5. Flutter partner screens only behind a feature flag after approval; consumer app unchanged.

## Gates before acceptance

Owner approval of this ADR (D-14 owners), confirmation that DEV admin is owner-provisioned only, and a Security review of the step-up requirement before any production admin use.
