# Implementation handoff

ADR-015 remains **PROPOSED**. Keycloak remains the recommended provider and TASK-005 remains **blocked** pending an explicit provider and fallback decision. TASK-006 remains **not started**. The local evidence supports review of the implementation design.

1. Record named product, security, operations and legal owners. Review the [token policy](token-lifecycle-policy.md), residual JWT window and [production gates](production-readiness.md). Record owner approval or concrete gaps in ADR-015.
2. After the gate, start TASK-006 with the canonical KUNDE UUID and unique verified `(issuer, subject)` mapping in PostgreSQL/Flyway. Reject malformed, unmapped, restricted and deleted principals. Cover idempotent creation and uniqueness under concurrency. Do not use a phone or email as the primary key. See [canonical identity](../canonical-identity-model.md).
3. Implement approved session UX and domain grants separately. Validate cross-app, issuer, audience, token type and authorized-party policy. Then rehearse provider failure, revoke and restore before onboarding real users.
