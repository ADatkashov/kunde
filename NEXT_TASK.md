# Next task — record the EP-002 provider and token policy decision

Prepare the owner review for self-hosted Keycloak and its fallback using [ADR-015](docs/architecture/adr/ADR-015-proposed-identity-provider.md), the [provider evaluation](docs/identity/poc/final-provider-decision-report.md) and the [Keycloak readiness package](docs/identity/keycloak-readiness/README.md).

1. Record the named product, security, operations and privacy/legal owners. Review the measured JWT acceptance window, online refresh policy, revocation SLO for sensitive actions and open privacy/operations/OTP gates.
2. Record the explicit provider/fallback and policy decision in ADR-015 when the owners approve it. Until then keep ADR-015 PROPOSED, TASK-005 blocked and TASK-006 not started.
3. After approval and the [D5 prerequisites](docs/roadmap/25-identity-ep002-design.md), begin TASK-006 with the Flyway schema and unique verified `(issuer, subject)` mapping to a canonical KUNDE UUID. Cover duplicate/concurrent creation and denial of malformed, unmapped or restricted principals.

**Review checks.** From the repository root run `git diff --check` and `node --check docs/identity/keycloak-readiness/verify-keycloak.mjs`. Read the [implementation handoff](docs/identity/keycloak-readiness/implementation-handoff.md) and [operational follow-ups](docs/identity/keycloak-readiness/operational-requirements.md). Record approval or precise blocking evidence in ADR-015 and the linked backlog. Production launch requires separate evidence and approval.
