# EP-002 requirement traceability

| Requirement / source | Design evidence | Implementation dependency / acceptance evidence |
|---|---|---|
| PRD AUTH-001 phone registration and OTP | `authentication-flows.md`, `otp-delivery-architecture.md`, `api-contracts.md` | IdP phone-first POC; generic outcomes, expiry/retry/anti-enumeration tests. |
| PRD AUTH-002 login, logout, recovery, sessions | `user-lifecycle.md`, `token-architecture.md`, `api-contracts.md`, `failure-and-recovery-scenarios.md` | Rotation/revoke, recovery and session tests; provider semantics validated. |
| PRD permissions: auth != authorization | `authorization-model.md`, `spring-boot-integration.md` | Tenant/resource deny tests for Consumer/Partner/Provider/Admin. |
| One user across apps | `canonical-identity-model.md`, `identity-architecture.md` | `iss+sub` mapping and multi-client POC; migration rehearsal preserves UUID. |
| ADR-009 OIDC/OAuth, provider pending | `provider-comparison.md`, `provider-decision-matrix.md`, Proposed ADR-015 | Explicit ADR acceptance after hard gates. |
| ADR-013 fail-closed foundation | `spring-boot-integration.md`, `token-architecture.md` | Retain issuer/audience validation; signed-token provider test. |
| D-05/D-07 security and access decisions | `security-threat-model.md`, `authorization-model.md`, `assumptions-and-open-decisions.md` | Product/security/legal ownership and negative tests. |
| D-15 launch country / localization | `kazakhstan-otp-provider-analysis.md`, `privacy-and-compliance.md`, `flutter-integration.md` | Current legal review, number parser and RU/KK/EN QA. |
| KZ SMS vendor independence | `kazakhstan-otp-provider-analysis.md`, `otp-delivery-architecture.md` | Contracted adapter POC, delivery receipts and spend controls. |
| Spring Boot 3.5.7 / Java 21 | `spring-boot-integration.md` | Compatible library/provider configuration and CI tests. |
| Existing Flutter foundation and design system | `flutter-integration.md` | Deep-link/device/accessibility QA with approved auth UI. |
| Cost and growth scenarios | `provider-cost-analysis.md` | Current quotes and real funnel measurements before budget. |
| Data-location/privacy obligations | `privacy-and-compliance.md` | Written counsel approval and data-flow/backup/log evidence. |

Related roadmap items: `docs/roadmap/25-identity-ep002-design.md`, `08-backend-roadmap.md`, `07-dependency-graph.md`, backlog EP-002. Provider selection remains blocked until evidence and owner decision are recorded.
