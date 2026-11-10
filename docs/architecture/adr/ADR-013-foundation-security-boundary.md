# ADR-013: Foundation Authentication Boundary

- **Status:** Accepted for the reversible foundation implementation; does not approve an OIDC vendor or close ADR-009/D-05/D-07.
- **Context:** No identity provider, issuer, audience, credential policy or token-issuance service is selected. Fake OTP or permissive anonymous protected routes would be unsafe and misleading.
- **Decision:** Support optional OIDC JWT resource-server verification using an explicitly configured issuer. Without an issuer, deny every route except health, capability metadata and empty read-only catalog/search. KUNDE does not issue or store credentials in this increment.
- **Consequences:** Foundation can run without invented identity behavior. Real user flows require provider review, audience/claim validation, role/resource authorization and security tests.
- **Alternatives:** Hard-coded demo users or bespoke OTP/session issuance (rejected: unresolved risk/provider); leave all routes anonymous (rejected: fail-open).
- **Revisit when:** ADR-009 and PRD identity decisions are approved and an issuer/test environment is available.
