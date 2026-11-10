# Identity POC test scenarios

All scenarios use local-only Keycloak and ZITADEL, synthetic identities, and the opt-in `identity-poc` backend profile. Results are in [test-results.md](test-results.md). A scenario is marked passed only after execution.

| ID | Scenario | Expected |
|---|---|---|
| P-01 | Start each pinned Compose project independently | Healthy service, isolated database and non-conflicting ports |
| P-02 | Fetch OIDC discovery document | Issuer exactly matches configured issuer and exposes authorization/token/JWKS/logout endpoints |
| P-03 | Fetch JWKS | Valid JSON key set is returned |
| P-04 | Mobile authorization | System browser, Authorization Code + PKCE S256, registered redirect URI and state/nonce validation |
| P-05 | Backend call without bearer token | 401 |
| P-06 | Valid token with configured issuer, audience and `kunde.poc` permission | 200 from `/api/v1/poc/whoami` |
| P-07 | Expired token or invalid signature | 401 |
| P-08 | Wrong issuer or audience | 401 |
| P-09 | Valid token lacking POC permission | 403 |
| P-10 | Refresh and refresh-token rotation | New access token; old refresh token rejected according to provider configuration |
| P-11 | Provider logout and local token clearing | Provider session ended where supported and local credentials removed |
| P-12 | Restart provider and inspect persisted test state | Test-only state survives normal restart; removable with explicit reset |
| P-13 | Build/analyze Flutter client | Static analysis and Android debug build succeed |

Run P-01/P-02/P-03 before attempting UI login. P-05 through P-11 require provider client setup, backend startup and interactive token acquisition. Do not use a password grant or disable signature validation to bypass a failure.
