# Identity implementation roadmap after design acceptance

Current reconciliation (2026-11-12, main 51374d1): ADR-015 is ACCEPTED for
synthetic implementation, with Keycloak primary and ZITADEL fallback. Historical
G0/G1 proposal wording below does not reverse that recorded owner approval.
PR #5 implements Consumer identity/profile and Flutter authentication UI; hosted
main Backend/Flutter/APK checks pass. G3/G5 remain partial (consent, session
administration and native Consumer device acceptance are incomplete). Production
G4/G7 approvals and operational evidence remain open. Manual Android E2E must
fail, with NOT_EXECUTED evidence, when scenario prerequisites are absent.
PR #14 adds the executable native fixture/scenario. Initial Android 30 runs verified
welcome RU/KK/EN but reached Keycloak's Cookie not found page before credentials;
HTTP probes passed. A real Cloud Chromium form/S256/API check passes independently.
Android35/Chrome124 run 43209945677 passes six targeted native login/profile/vault/offline/logout checks on source db13a26. Browser input uses a fixture-bound
DevTools adapter; native accessibility, iOS and complete G5 acceptance remain open.
See [scoped evidence](consumer-validation/README.md).

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
