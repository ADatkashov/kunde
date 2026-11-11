# Provider recommendation — recovery 3.0

This is the historical 3.0 checkpoint. The [final provider decision report 4.0](final-provider-decision-report.md) supersedes its recommendation and ZITADEL status.

**Recommendation: do not approve a production provider yet.** Keycloak 26.8.2 is the only provider with demonstrated Android Flutter Authorization Code + PKCE, real provider JWT validation by Spring Security, HTTP 200 on the protected API, refresh renewal, and logout followed by an interactive login form. That is meaningful evidence for the priority integration path, and makes Keycloak the current POC front-runner for further validation, not a production selection.

ZITADEL 4.19.5 now starts cleanly and serves discovery/JWKS with all four local containers healthy. Its native app, project, role/audience scopes and test user are not configured, so it has not been fairly compared on Flutter compatibility, Spring token mapping, lifecycle or security. Earlier discovery timeout occurred under host pressure; this run's startup completed in 96.1 seconds and discovery returned promptly after health checks. Do not score that setup gap as an authentication failure.

## Evidence-led comparison

| Area | Keycloak 26.8.2 | ZITADEL 4.19.5 | Current conclusion |
|---|---|---|---|
| Mobile OIDC/PKCE | Android system-browser flow completed with synthetic user | No app/client flow run | Keycloak passes positive path; no equivalence conclusion |
| Spring compatibility | Real JWT signature, issuer, audience, expiry and POC scope accepted; HTTP 200 | No token presented | Keycloak positive path only |
| Negative JWT/security | Deterministic Spring matrix passed; no live Keycloak negative-token matrix | Not tested | Insufficient for provider ranking |
| Refresh/logout | Refresh and renewed API pass; browser login form after logout | Not tested | Partial lifecycle evidence for Keycloak |
| Administrative effort | Realm imported; persistent realm needed explicit scope repair and subject mapper | POC setup requires project/app/role/user via console | Not comparable; different unfinished setup stages |
| Deployment | Two local containers incl. PostgreSQL; previously measured idle snapshot ~918 MiB server / ~54 MiB DB | Four components incl. API, Login, PostgreSQL, Traefik; latest startup 96.1 sec | POC topology only; no equivalent fresh resource snapshot/load data |
| Operations/scalability | HA, backup restore, upgrades and load untested | Same | Unknown |
| Data residency | Self-host location under operator control in principle; legal design not reviewed | Same for self-host; hosted options not assessed | Legal review required |
| Lock-in/cost | OIDC portability intent; export/migration and costs untested | OIDC portability intent; export/migration and costs untested | Unknown |

The successful Keycloak path raises its confidence for EP-002 technical implementation behind the existing provider abstraction, but provider approval remains an owner decision. Finish equivalent ZITADEL test, live negative-token/security cases, full lifecycle and legal/operational/commercial review before updating ADR-015 from PROPOSED. TASK-005 requires explicit approval; TASK-006 is not satisfied by POC evidence.
