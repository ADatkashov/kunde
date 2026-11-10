# Identity implementation roadmap after design acceptance

Sequence is gated and evidence-driven; estimates intentionally omitted until owners and provider are known.

| Gate | Work | Dependency / exit evidence |
|---|---|---|
| G0 — Accept design | Review proposed ADR-015; approve final identity portability boundary and OTP ownership | Product, security, legal/privacy, backend/mobile, operations owners record decision. |
| G1 — Select finalist | Compare Keycloak/ZITADEL/customized managed option with current quotes and region/subprocessor answers | Hard gates in decision matrix; legal location/transfer sign-off; operations capacity accepted. |
| G2 — POC | Test phone-first custom flow, OTP adapter, PKCE Flutter callbacks, audience/issuer Spring validation, session rotation, export | No production credentials; isolated tenant/test numbers; threat review and measured latencies/cost. |
| G3 — Data/API implementation | Add identity schema/entities/migrations, mapping, lifecycle APIs and consent/audit contracts | Approved data model, retention and API contract; migration/rollback plan. |
| G4 — IdP and delivery integration | Configure environments/clients, secrets, MFA, delivery adapter, monitoring and spend controls | Provider contract, DNS/redirect domains, template/sender approvals, secret rotation and failover runbooks. |
| G5 — Flutter implementation | Login/register/challenge/recovery/session UX, secure token storage, deep links, RU/KK/EN/accessibility | Design QA and device callback testing; no insecure storage. |
| G6 — Authorization integration | Resource-level consumer/partner/provider/admin policies, memberships, denial/audit paths | Business roles/owners defined; negative tests and separation-of-duty review. |
| G7 — Readiness | Abuse, outage, migration, backup/restore, key rotation, privacy, cost and support rehearsals | Launch gates and measurable SLOs/alerts; owners sign readiness. |

Current prerequisites: EP-001 foundation is locally complete per prior repository status, but real OIDC provider/token verification, CI remote execution and dependency scanning remain separate controls. EP-003 profile and partner/provider features depend on stable KUNDE user ID and authorization policy. Payments/support/admin require additional high-risk and operational controls.
