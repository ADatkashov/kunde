# Assumptions and open decisions

## Assumptions

- KUNDE owns a stable UUID user ID independent of IdP and phone/email.
- OIDC Authorization Code + PKCE is the native Flutter flow; APIs receive resource-audience access tokens.
- IdP owns authentication challenge and token semantics; KUNDE owns authorization and canonical mapping.
- First market is Kazakhstan, with RU/KK/EN product support and future international numbers.
- Phone OTP is proposed as primary consumer bootstrap, subject to SIM-swap risk acceptance and recovery design.
- Provider pricing snapshot is 2026-11-10 public pricing; prices/limits may change and are not commercial offers.

## Decisions required before implementation

| Decision | Owner(s) | Options / evidence needed | Blocking point |
|---|---|---|---|
| Final IdP | Product + security + operations + legal | Keycloak, ZITADEL, Auth0, Cognito, Firebase; weighted matrix, POC, quotes and region proof | Before G1/G2. |
| Data residency interpretation | Privacy counsel | Current law, processor locations, replicas, logs, backups, support access and cross-border transfer | Before any real personal data/provider account. |
| IdP deployment model | Operations + security | Self-host in approved KZ region vs managed contractual region | Before architecture acceptance. |
| Phone-first login and recovery | Product + security/support | SMS-only bootstrap, alternate factor, lost number and recycled number policy | Before auth UX build. |
| OTP ownership | Security + IdP integrator | IdP generated/verified plus send adapter; vendor delegated OTP only through supported SPI | Before adapter contract. |
| Contact uniqueness | Product + data | Unique verified phone vs shared/family/business phone policy | Before schema constraints. |
| Session/revocation SLO | Security + operations | Access lifetime, refresh lifetime, forced revocation propagation | Before production. |
| Admin identity policy | Security + operations | Separate tenant/realm or separate client/policy, phishing-resistant factor, JIT elevation | Before admin portal. |
| SMS supplier / fallback | Procurement + operations + privacy | Written rates, KZ coverage, templates/sender, latency, SLA and data processing | Before production send. |
| Retention/deletion | Privacy/legal + finance | Security logs, identity proof, account deletion, legal holds and financial records | Before lifecycle implementation. |

## Not assumed

No provider is selected or configured; no SMS or WhatsApp integration exists; no quote, SLA, residency guarantee, telecom approval, legal advice, delivery latency or real-user cost is claimed. Weighted scores are provisional and must be updated using comparable evidence.
