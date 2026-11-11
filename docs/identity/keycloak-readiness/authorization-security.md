# Authorization security

The POC route uses a coarse `kunde.poc` scope. In the drill realm, the consumer scope is restricted by a consumer role scope mapping. A partner user and partner application have their own role/scope path and share the test API audience so denial exercises authorization after JWT authentication. A separate consumer client omits the API audience.

The isolated Spring tests use generated keys and signed fixtures to isolate wrong issuer, invalid signature, wrong audience, expiry, future validity and absent scope. The previous 4.0 provider comparison also showed cross-provider JWT rejection. Cross-provider rejection varies the issuer and signing key together. Real role-to-scope behavior is recorded separately from those fixtures.

Production KUNDE authorization must verify the mapped account, app/client contract and business grant at the domain boundary. See [authorization model](../authorization-model.md).

## Observed results

| Input to the same protected Spring route | Result and evidence |
|---|---|
| Consumer token with consumer role and API audience | HTTP 200, real Keycloak token |
| Same consumer client with synthetic partner user and no consumer role | HTTP 403, real Keycloak token |
| Partner-app token with the partner scope and the same API audience | HTTP 403, real Keycloak token |
| Consumer token from alternate client without the expected API audience | HTTP 401, real Keycloak token |
| Missing bearer | HTTP 401, live route |
| Expired genuine token outside Spring tolerance | HTTP 401, live route |
| Wrong issuer, bad signature, wrong audience, expired and future token | Individually HTTP 401 in generated-key HTTP fixtures |
| Valid fixture without the required scope | HTTP 403 in HTTP fixture |
