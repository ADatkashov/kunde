# ZITADEL POC setup

## Local instance

Run `Start-IdentityPoc.ps1 -Provider zitadel`. This starts ZITADEL 4.19.5, its matching Login UI, PostgreSQL 17.10 and a local Traefik router under the isolated `kunde-zitadel-poc` network/project. The router binds only to `127.0.0.1:8280` and serves `http://localhost:8280`; no port 443 or public hostname is exposed. The local Compose setup is adapted from the [official ZITADEL Compose deployment](https://github.com/zitadel/zitadel/blob/v4.19.5/deploy/compose/docker-compose.yml).

Discovery URL: `http://localhost:8280/.well-known/openid-configuration`. Wait for Compose health checks. Bootstrap secrets are in the ignored `.env` file. In the persisted instance the working administrator login used the bootstrap username suffixed by `@zitadel.localhost`. The stored `@localhost` login returned `QUERY-Dfbg2` (user not found).

## Create equivalent project and app

1. Open `http://localhost:8280/ui/console/` and sign in using the generated local admin credentials.
2. Create organization `KUNDE Development` and project `KUNDE POC` in it. Record the organization and project IDs.
3. Add role key `kunde.poc` and role key `consumer-poc` to the project; assign both to the synthetic user. Do not create an operator grant for that user.
4. Add Native application `kunde-consumer-poc`. Set response type Code, grants Authorization Code and Refresh Token, token endpoint auth method None, access token type JWT, access-token role assertion and skip Native success page. Set both redirects to `com.kunde.mobile:/oauth2redirect`. Enable Development Mode only for this loopback POC.
5. Create a synthetic human with a verified local `.test` email, random password and no external delivery. Use the account's full preferred login name for its organization. Assign `kunde.poc` and `consumer-poc` in the project.
6. Request the following scopes with AppAuth PKCE S256. Replace angle-bracket values with local IDs.

```text
openid offline_access urn:zitadel:iam:org:id:<ORG_ID> urn:zitadel:iam:org:project:id:<PROJECT_ID>:aud urn:zitadel:iam:org:project:role:kunde.poc urn:zitadel:iam:org:projects:roles
```

Start the backend POC with issuer `http://localhost:8280`, audience equal to the project ID and `POC_ZITADEL_ORGANIZATION_ID` equal to the organization ID. Set `SERVER_ADDRESS=127.0.0.1` for the local API. With JWT role assertion on, the actual JWT carried `jti` and a signed `urn:zitadel:iam:org:project:<PROJECT_ID>:roles` object mapping role keys to organizations. It did not contain `scope`. The POC checks the signed `kunde.poc` grant for the configured organization in that project. A requested role scope alone supplies no authority. The POC also requires ZITADEL's access-token identifier because its ID token can share the project audience. This token-profile rule applies only to this POC and pin.

ZITADEL also supports opaque access tokens through authenticated introspection. It requires backend credentials and an online IdP request, with availability, latency and cache-freshness trade-offs. Direct JWT verification uses the existing resource-server boundary and local validation. Revocation of already issued JWTs depends on expiry or an additional online check. [Native configuration](https://zitadel.com/docs/guides/manage/console/applications-overview), [scopes](https://zitadel.com/docs/apis/openidoauth/scopes), [claims](https://zitadel.com/docs/apis/openidoauth/claims), [introspection](https://zitadel.com/docs/guides/integrate/token-introspection)

## Reset and upgrade

Stop with `Stop-IdentityPoc.ps1 -Provider zitadel -RemoveLocalData`. Upgrade only after reviewing release notes and changing both API and Login image pins together. This local test does not validate HA, external TLS, backup restore or production hardening.

Official references: [Compose deployment](https://zitadel.com/docs/self-hosting/deploy/compose), [Native application settings](https://zitadel.com/docs/guides/manage/console/applications-overview), [ZITADEL scopes](https://zitadel.com/docs/apis/openidoauth/scopes), [recommended flows](https://zitadel.com/docs/guides/integrate/login/oidc/oauth-recommended-flows).
