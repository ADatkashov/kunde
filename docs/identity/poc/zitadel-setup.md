# ZITADEL POC setup

## Local instance

Run `Start-IdentityPoc.ps1 -Provider zitadel`. This starts ZITADEL 4.19.5, its matching Login UI, PostgreSQL 17.10 and a local Traefik router under the isolated `kunde-zitadel-poc` network/project. The router binds only to `127.0.0.1:8280` and serves `http://localhost:8280`; no port 443 or public hostname is exposed. The local Compose setup is adapted from the [official ZITADEL Compose deployment](https://github.com/zitadel/zitadel/blob/v4.19.5/deploy/compose/docker-compose.yml).

Discovery URL: `http://localhost:8280/.well-known/openid-configuration`. Wait for Compose health checks. Initial organization administrator login and bootstrap secrets are in the ignored `.env` file.

## Create equivalent project and app

1. Open `http://localhost:8280/ui/console/` and sign in using the generated local admin credentials.
2. Create a project named `KUNDE POC`.
3. Add role key `kunde.poc` and role key `consumer-poc` to the project; assign both to the synthetic user. Do not create an operator grant for that user.
4. Add a Native application named `kunde-consumer-poc`. Use Authorization Code with PKCE (S256), set the redirect URI to `com.kunde.mobile:/oauth2redirect`, and set post-logout redirect to the same value. Enable Development Mode only on this disposable local instance because it uses HTTP/custom redirect.
5. Configure the project as audience for the Native application (project/app settings or request the documented project audience scope). Record the project ID; set it as `OIDC_AUDIENCE` for the backend and pass `urn:zitadel:iam:org:project:id:<PROJECT_ID>:aud` in OIDC scopes.
6. Create a synthetic human account in the local organization with login name ending `.test` (or use an organization-only username), unique random password, and no real email/phone. Verify it locally if the UI requires a contact proof; do not configure external delivery.
7. Request scopes `openid profile offline_access urn:zitadel:iam:org:project:id:<PROJECT_ID>:aud urn:zitadel:iam:org:project:role:kunde.poc urn:zitadel:iam:org:project:role:consumer-poc`.

ZITADEL encodes project roles using reserved role scopes/claims; the backend's **POC-only** converter maps the explicit `...role:kunde.poc` scope into the common test authority `SCOPE_kunde.poc`. This is solely for equivalent API scope tests, not a recommended production role model.

## Reset and upgrade

Stop with `Stop-IdentityPoc.ps1 -Provider zitadel -RemoveLocalData`. Upgrade only after reviewing release notes and changing both API and Login image pins together. This local test does not validate HA, external TLS, backup restore or production hardening.

Official references: [Compose deployment](https://zitadel.com/docs/self-hosting/deploy/compose), [Native application settings](https://zitadel.com/docs/guides/manage/console/applications-overview), [ZITADEL scopes](https://zitadel.com/docs/apis/openidoauth/scopes), [recommended flows](https://zitadel.com/docs/guides/integrate/login/oidc/oauth-recommended-flows).
