# 05 — Engineering Epics

Machine-readable epic IDs, scope and release links are canonical in [`backlog/epics.yaml`](backlog/epics.yaml). The 27 epics cover the 27 requested capability areas without implying every area ships in MVP.

| Epic | Objective / release | Dependencies and boundary |
|---|---|---|
| EP-001 Project foundation | Repository conventions, environments, contracts / Foundation | Architecture baseline |
| EP-002 Authentication & identity | Safe sign-in and sessions / Foundation-MVP | Complete design gates in [25-identity-ep002-design.md](25-identity-ep002-design.md), D-05/D-07, legal/data review, OTP provider selection |
| EP-003 User profile | Preferences and account / MVP | EP-002, D-15 |
| EP-004 Location & address | Address/serviceability / MVP | Maps/geocoding choice D-11; fallback policy |
| EP-005 Global search | Localized available discovery / MVP | Catalog, location |
| EP-006 Marketplace catalog & categories | Orderable catalog and category controls / MVP | D-01, partner readiness |
| EP-007 Business profiles | Verified partner/branch information / MVP | D-07, contract and moderation |
| EP-008 Partner platform | Partner onboarding and work queue / MVP | EP-006–007, agreed workflow |
| EP-009 Provider platform | Conditional dispatch/provider tooling / conditional MVP or later | D-02; provider/fleet terms and verification |
| EP-010 Order management | Durable order lifecycle / MVP | D-01, D-05/D-06, database |
| EP-011 Booking management | Appointment lifecycle / later | Category selection and availability rules |
| EP-012 Payments | Provider abstraction and verified financial state / MVP gate | D-03/D-04, legal/provider |
| EP-013 Refunds & settlements | Reconciliation and controlled adjustments / MVP gate | EP-012, D-06/D-14 |
| EP-014 Delivery & logistics | Fulfillment status and dispatch / conditional | D-02, integration/operations |
| EP-015 Notifications | Transactional status delivery / MVP | Identity/contact consent, provider D-11 |
| EP-016 Reviews & ratings | Trust feedback/moderation / post-MVP | D-13, moderation staffing |
| EP-017 Promotions & loyalty | Measured funded growth / post-MVP | D-13, finance attribution |
| EP-018 Customer support | Case and escalation workflows / MVP | Policy, staffing, admin access |
| EP-019 Admin portal | Scoped internal operations / MVP | RBAC, audit, separation of duties |
| EP-020 Analytics | Product/operations metrics / MVP minimum then expand | Event definitions, privacy, D-08/D-12 |
| EP-021 AI platform | Grounded discovery; action preparation later | Data/privacy approval, evaluations, authorization |
| EP-022 Security & compliance | Secure defaults and launch assurance / all releases | D-07/D-08, jurisdiction review |
| EP-023 Observability | Service health and incident response / Foundation-MVP | D-12, owners and alert policy |
| EP-024 Internationalization | Language-ready experience / Foundation-MVP | D-15, human translation/legal review |
| EP-025 Infrastructure & DevOps | Repeatable deploy, secrets, backup/restore / Foundation | Hosting/residency procurement |
| EP-026 Testing & quality | Automated and operational quality gates / all releases | Test environments and stable contracts |
| EP-027 Database & data lifecycle | Schema ownership, migrations, retention / Foundation-MVP | Architecture, privacy and domain owners |

Every epic's acceptance is: its agreed release scope passes feature/task DoD, has named product and operational owner, no unresolved critical dependency, telemetry and recovery behavior are demonstrated, and release gate evidence is recorded. Out-of-scope items remain deferred even when their epic exists.

