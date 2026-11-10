# KUNDE Development Foundation 1.0

This directory records the first implementation increment, verification evidence and explicit limits. It does not approve unresolved product, legal, vendor, finance or data-residency decisions.

## Status

The foundation adds PostgreSQL/Flyway bootstrap, API correlation/error contracts, health and capability endpoints, conditional OIDC resource-server boundary, CI, local container instructions, and a Flutter status shell with RU/KK/EN localization scaffolding. Build/test verification is tracked in `implementation-status.md`; marketplace, login and AI remain disabled by default.

## Documents

- [Documentation review](documentation-review.md) and [implementation scope](implementation-scope.md)
- [Project structure](project-structure.md) and [local development](local-development.md)
- [Backend](backend-foundation.md), [mobile](mobile-foundation.md), [database](database-and-migrations.md), [auth/security](authentication-and-security.md), [API contracts](api-contracts.md)
- [DevOps](devops-and-environments.md), [observability](observability.md), [AI boundaries](ai-integration-boundaries.md), [tests](testing-strategy.md)
- [Implementation status](implementation-status.md) and [known limitations](known-limitations.md)

## Architecture decisions

See [ADR-013](../architecture/adr/ADR-013-foundation-security-boundary.md) and [ADR-014](../architecture/adr/ADR-014-unavailable-catalog-default.md). Earlier ADRs remain Proposed for review; this implementation follows their reversible stack recommendations without claiming governance approval.
