# 25 — EP-002 Identity & Access design deliverables

**Status:** design package and bounded 4.0 provider evaluation prepared. Self-hosted Keycloak is recommended for review. Owner approval and the privacy, commercial and operations gates remain open. See the [4.0 decision report](../identity/poc/final-provider-decision-report.md).

## Completed design outputs

The companion package is indexed at [`docs/identity/README.md`](../identity/README.md) and contains the 23 requested specification documents plus five Mermaid diagrams. It covers provider evidence/cost, KZ messaging, canonical identity, flows, lifecycle, tokens, authorization, adapters, Spring, Flutter, APIs/data, threats/privacy, failure recovery, MVP, roadmap, open decisions and traceability. Proposed architecture is in [ADR-015](../architecture/adr/ADR-015-proposed-identity-provider.md).

## EP-002 sequencing and dependencies

| Order | Work item | Dependency / exit gate |
|---|---|---|
| D1 | Review design and accept/revise ADR-015 | Named product, security, legal/privacy and operations owners; explicit acceptance record. |
| D2 | Close Kazakhstan data-location and processor review | Current-law counsel analysis covering IdP, SMS, logs, backups, support, telemetry and cross-border transfer. Blocks any live personal data. |
| D3 | Obtain commercial/vendor evidence | Quotes for MAU/DAU, features, OTP route, SLA, export, data copies, contract, sender/template requirements, status semantics and support. |
| D4 | Provider + adapter POC | The [4.0 comparison](../identity/poc/final-provider-decision-report.md) and [Keycloak security drill](../identity/keycloak-readiness/README.md) record provider and lifecycle evidence. Kazakhstan phone-first and SMS adapter checks remain open. |
| D5 | Implement identity schema and backend mapping/API | Depends on accepted ADR, canonical identity/data model, lifecycle/retention and provider migration/export proof. |
| D6 | Implement Flutter login/session UX | Depends on provider proof, approved callback domains and design/localization/accessibility review. |
| D7 | Implement authorization grants and app boundaries | Depends on domain owners for consumer/partner/provider/admin resource scopes and separation-of-duty rules. |
| D8 | Production readiness | Depends on abuse/cost controls, key rotation, outage recovery, backup/restore, revocation SLO, legal approval and support/on-call runbooks. |

D2 and D3 can progress in parallel. D5 and D6 may be developed in parallel only after the OIDC/API contracts are stable. D8 is a production gate, not an optional backlog item. EP-003 profile depends on D5 stable user ID. Partner/provider operations and admin depend on D7 scoped grants. Orders/support depend on correct owner mapping and session recovery.

## Backlog linkage

- `TASK-005` remains **blocked** until the final IdP/fallback decision is approved; this design proposes candidates but does not close that task.
- `TASK-006` remains **not started** and depends on TASK-005; its scope must follow the accepted provider/API design.
- `FEAT-003` maps to PRD `AUTH-001` and `AUTH-002` and contains implementation scope, not evidence of implementation.
- EP-001 local completion does not establish a real OIDC issuer, remote CI execution or production security posture.
- `docs/identity/poc/` records observed POC results. `ADR-015` remains PROPOSED and the provider/fallback selection still requires explicit approval.

The provider experiment changes only the local POC authorization path. EP-002 implementation remains gated.

The [implementation handoff](../identity/keycloak-readiness/implementation-handoff.md) sequences the owner decision and canonical UUID mapping. The [operational backlog](../identity/keycloak-readiness/operational-requirements.md) assigns exit evidence for TLS, PostgreSQL, restore, HA, monitoring, capacity, migration, legal and OTP work.

