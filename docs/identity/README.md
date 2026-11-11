# KUNDE Identity & Access — EP-002 design package

**Status:** design proposal, not implementation approval. **As of:** 2026-11-10.

This package translates PRD AUTH-001/AUTH-002 and ADR-009 into an implementation-ready, provider-neutral design. The preferred direction is a stable KUNDE user key mapped to OIDC `(issuer, subject)`, a standards-based IdP, domain-owned authorization, and replaceable Kazakhstan messaging adapters. Provider choice and production launch remain gated on legal/data-residency review, current commercial quotes, operational ownership, and a proof of concept.

## Documents

1. [Identity architecture](identity-architecture.md)
2. [Provider comparison](provider-comparison.md)
3. [Weighted decision matrix](provider-decision-matrix.md)
4. [Cost scenarios](provider-cost-analysis.md)
5. [Kazakhstan OTP delivery providers](kazakhstan-otp-provider-analysis.md)
6. [Canonical identity model](canonical-identity-model.md)
7. [Authentication flows](authentication-flows.md)
8. [User lifecycle](user-lifecycle.md)
9. [Token architecture](token-architecture.md)
10. [Authorization model](authorization-model.md)
11. [OTP delivery architecture](otp-delivery-architecture.md)
12. [Spring Boot integration](spring-boot-integration.md)
13. [Flutter integration](flutter-integration.md)
14. [Proposed API contracts](api-contracts.md)
15. [Logical data model](data-model.md)
16. [Security threat model](security-threat-model.md)
17. [Privacy and compliance questions](privacy-and-compliance.md)
18. [Failure and recovery scenarios](failure-and-recovery-scenarios.md)
19. [MVP scope](mvp-identity-scope.md)
20. [Implementation roadmap](implementation-roadmap.md)
21. [Assumptions and open decisions](assumptions-and-open-decisions.md)
22. [Requirement traceability](traceability.md)
23. [Architecture diagrams](diagrams/README.md)

The proposed architecture ADR is [ADR-015 (PROPOSED)](../architecture/adr/ADR-015-proposed-identity-provider.md). No accepted ADR was changed. Roadmap changes are recorded in [EP-002 sequencing](../roadmap/25-identity-ep002-design.md).

See the [Keycloak security and readiness package](keycloak-readiness/README.md) for live lifecycle checks, the proposed token policy and the implementation handoff.

## Read this before implementation

- Use OIDC Authorization Code + PKCE in the system browser for Flutter; never use an embedded WebView or a native client secret.
- Let the IdP own authentication challenges, credential proofs and tokens. KUNDE owns its permanent user key, domain permissions and business memberships.
- Do not treat phone number, email, an IdP role, or a client-supplied tenant ID as a KUNDE authorization decision.
- SMS providers are transport adapters. Their public prices and feature descriptions are not delivery guarantees or signed commercial terms.
- OTP limits in these specifications are initial design values for threat modeling and usability trials, not vendor defaults or legal requirements.
- Do not configure a real provider or create migrations until the proposed ADR and the explicit launch gates are accepted.

## Evidence labels

**Verified** means supported by an official public source linked in the relevant document. **Estimate** means arithmetic using an explicitly named public pricing tier. **Assumption** identifies a design choice to validate. **Vendor confirmation required** means pricing, residency, delivery, SLA, feature status, contract or legal-entity requirement has not been evidenced publicly.
