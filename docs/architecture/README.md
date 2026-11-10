# KUNDE Technical Architecture Specification 1.0

Status: **architecture recommendation for product/engineering review**, not an implementation approval. Date: 2026-11-10. Source baseline: `../product/PRD-1.0.md` and all files in `../product/PRD-1.1/`.

## Recommended direction

Start with a **domain-modular Spring Boot backend deployed as one application**, PostgreSQL as the system of record, Flutter for the consumer app, versioned REST APIs, and durable outbox-based asynchronous work. Avoid a broker, search cluster, Kubernetes and service mesh until the workload and team justify their operational cost. Introduce managed queue/search capabilities behind interfaces when concrete requirements demand them. AI is a policy-gated orchestration module and never queries databases directly.

For Kazakhstan personal data, design initial authoritative personal-data storage and processing around an in-country deployment. The current official Kazakhstan rules describe storage in a database located in Kazakhstan; cross-border processing/transfers need a separate legal basis/consent review. This is an architecture constraint pending counsel’s applicability analysis, not legal advice: [Kazakhstan Personal Data Law](https://old.adilet.zan.kz/eng/docs/Z1300000094), [collection and processing rules](https://old.adilet.zan.kz/eng/docs/V2000021498). Confirm amendments and vendor region capabilities at procurement.

## Document map

| File | Scope |
|---|---|
| 01–05 | Overview, principles, context, decision summary, technology comparison |
| 06–10 | Backend, domain boundaries, consumer mobile, partner/provider, admin |
| 11–12 | Database architecture and logical data model |
| 13–16 | API, events, order/booking/payment, search/geolocation |
| 17–18 | AI platform and security/threat model |
| 19–20 | Infrastructure/deployment and CI/CD |
| 21–23 | Observability, scalability, reliability/DR |
| 24–26 | Integrations, localization, privacy/compliance |
| 27–31 | Testing, cost/capacity, extraction roadmap, risks, traceability |

`diagrams/` contains 13 standalone Mermaid views. `adr/` contains ADR-001 through ADR-012, each with context, options, decision, consequences, risks and revisit conditions. Review sequence: 01–05 for shape and stack; 06–17 for components/data/APIs/transactions/AI; 18–26 for risk, deployment and privacy; 27–31 for verification, cost, extraction, risks and traceability.

## Decision status

Recommendations in this specification are proposed, not previously approved choices. Confirm cloud, payment, OTP, map, AI, search and messaging vendors through due diligence. No production code, deployment or infrastructure changes are part of this deliverable.

## Cross-document invariants

- Each domain owns its records; modules communicate through declared interfaces/events, not another module’s tables.
- Order, booking and payment are distinct linked aggregates. Provider-confirmed financial state is authoritative.
- Mutations are authorized, idempotent, versioned, auditable and recoverable.
- User confirmation is bound to an exact AI action draft; all execution repeats authorization and business validation.
- Default deployment is one country/region boundary at a time; cross-border movement of personal data is denied until reviewed and approved.
- Requirements traceability uses PRD IDs; existing demo source code is not evidence that architecture requirements are implemented.
