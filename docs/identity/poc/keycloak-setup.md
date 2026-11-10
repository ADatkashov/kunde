# Keycloak POC setup

## Local instance

Start with `Start-IdentityPoc.ps1 -Provider keycloak`. Image is pinned to 26.8.2; data lives only in the `kunde-keycloak-poc` Compose project and its `keycloak-db` volume. Admin realm is the isolated `master`; imported test realm is `kunde-dev`.

Discovery URL: `http://localhost:8180/realms/kunde-dev/.well-known/openid-configuration`.

The imported realm config creates:

- `kunde-consumer-poc`: public client, Authorization Code enabled, direct access grants and implicit flow disabled, PKCE method S256, app callback and local smoke callback allowlisted.
- `kunde-api`: audience marker client; API token gets `aud=kunde-api` through a default audience mapper.
- `kunde.poc` default client scope and `consumer-poc` / `operator-poc` realm roles.
- `basic` client scope with the `Subject (sub)` mapper (`oidc-sub-mapper`), assigned as a default scope. This is required for the tested API response. An initialized realm may not be changed by `--import-realm`; apply the mapper to the existing local realm as needed.
- `offline_access` is optional for the mobile client and was enabled for refresh verification.
- registration, self-service password reset and SMS/email delivery disabled for the synthetic test realm.

## Synthetic user

1. Open `http://localhost:8180/admin/`, read the admin password locally from `keycloak/.env`.
2. Select realm `kunde-dev` → Users → Create new user. Use username `kunde-consumer-poc`, email `kunde-consumer@example.test`; do not use a real address.
3. Set email verified only if needed for the POC. Create a unique local password through the console; require no action at next sign-in. Never commit it.
4. Assign only the `consumer-poc` realm role. `operator-poc` exists for negative-role comparison and must not be assigned to the consumer test user.

## Expected client request

- Issuer: `http://localhost:8180/realms/kunde-dev`
- Client ID: `kunde-consumer-poc`
- Redirect: `com.kunde.mobile:/oauth2redirect`
- Scopes used in the verified app run: `openid offline_access kunde.poc` (`profile` and `email` were omitted because not required by this POC client).
- Code flow: authorization code + PKCE S256 only; no client secret, password grant or implicit flow.
- API audience: `kunde-api`.

For mobile tests, start the backend with `identity-poc` profile and matching issuer/audience. Keycloak local test tokens are signed by the local realm key; the API obtains JWKS from realm discovery.

## Reset and upgrade

Stop with `Stop-IdentityPoc.ps1 -Provider keycloak -RemoveLocalData`. To upgrade, change the image pin only after reviewing official release notes and repeat the full test matrix. No data migration from this ephemeral realm is in scope.

Official reference: [Keycloak 26.8.2 server admin guide](https://www.keycloak.org/docs/26.8.2/server_admin/) and [Docker setup](https://www.keycloak.org/getting-started/getting-started-docker).
