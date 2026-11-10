# 04 — Architecture Decisions Summary

The detailed records are under `adr/`. All choices below are **recommendations for review**, not approvals.

| ADR | Recommendation | Main alternative rejected for initial stage | Revisit when |
|---|---|---|---|
| 001 | Modular monolith, domain modules | Microservices from day one | Module scaling/team/failure isolation trigger |
| 002 | Flutter consumer app; keep role surfaces separable | React Native or fully native | Platform-specific UX/performance constraints demonstrated |
| 003 | Java 21 + Spring Boot | Kotlin or other backend runtime | Team skills/productivity evidence changes |
| 004 | PostgreSQL as transactional source of truth | Multiple databases by domain at launch | Proven scale or isolation need |
| 005 | PostGIS extension for geo queries | External geo database at launch | Query/vendor constraints justify alternative |
| 006 | PostgreSQL outbox first; managed queue for delivery; Kafka later | Kafka cluster on day one | Sustained event throughput/replay/consumer count warrants Kafka |
| 007 | PostgreSQL search initially; OpenSearch when relevance/facets/scale require | Search cluster at launch | Search workload/quality threshold measured |
| 008 | Provider-neutral AI gateway with tool allowlist | Single model SDK embedded in domains | Provider capability/cost review |
| 009 | Standards-based OIDC/OAuth approach; provider decision pending | Bespoke credential/session protocol | Security/team/region fit assessed |
| 010 | Payment adapter, verified webhooks/status checks, immutable journal | Direct vendor coupling or wallet-first | Contract/provider semantics verified |
| 011 | Vendor-neutral containers/IaC; managed services in verified Kazakhstan region | Self-managed Kubernetes on day one | Availability, operational team or scale needs |
| 012 | Single home region/country partition initially; no global active-active writes | Global active-active database | Legal approvals and measured regional demand |
| 015 | Proposed portable KUNDE identity boundary: stable internal user ID + OIDC provider + replaceable OTP transport; provider not selected | Bespoke token issuer or identity keyed by phone/provider subject | After Kazakhstan privacy/legal review, comparable quotes, operations ownership and finalist POC; see [ADR-015](adr/ADR-015-proposed-identity-provider.md) |

Decisions D-01 through D-15 in PRD 1.1 remain product/operations/legal decisions; architecture must not silently resolve them.
