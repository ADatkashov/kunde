# ADA-73 / TASK-007 — Consumer consent API (synthetic scope)

The existing Flyway V4 ledger is the source of truth. No policy is seeded or approved by this change.

All endpoints require a valid consumer JWT with the existing `consumerAccessPolicy` gate and an ACTIVE provisioned account. Responses use `Cache-Control: no-store`.

- `GET /api/v1/me/consents`: approved policies and current user-specific grant state; absent events are false.
- `PUT /api/v1/me/consents/{policyId}`: explicitly grant an approved policy version.
- `DELETE /api/v1/me/consents/{policyId}`: explicitly withdraw an approved policy version.

Unknown or unapproved policy IDs fail closed. Writes are serialized per account/policy and repeat actions do not append duplicate consecutive events. Other users' records are not addressable. The immutable ledger retains withdrawal history.

**Not production-approved:** Legal/privacy must approve the exact purpose, localized policy text, hash, retention, withdrawal side effects and operational policy publication before any real policy is marked approved. No policy is inserted automatically. No consent is inferred from authentication. This change does not implement downstream revocation effects, user-facing Flutter UX or production privacy signoff.

Validation: `cd backend && mvn verify` with configured test PostgreSQL; review the new `ConsumerConsentServiceIntegrationTest`. CI results are required before merge.
