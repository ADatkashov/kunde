# KUNDE Identity Provider POC

**Local development only.** Two separately named Compose projects and databases; no production service, external paid service, real personal data or SMS channel is used. Container versions are pinned: Keycloak 26.8.2, ZITADEL 4.19.5, PostgreSQL 17.10-alpine, Traefik 3.7.7. The ZITADEL 4.20.0 release notes contained an instruction to skip that release, so this POC pins the preceding patched 4.19.5 line instead. Re-evaluate versions before repeating the POC.

Start with the [final provider decision report 4.0](final-provider-decision-report.md) for the outcome and approval gates.

## Prerequisites

- Docker Desktop/Engine with Compose v2 and at least 4 GB available RAM if both providers run together.
- Java 21, Maven and Flutter/Android SDK for the backend/mobile checks; use PowerShell 7 (`pwsh`) for local scripts.
- Android emulator or device for interactive Flutter login. For this loopback-only POC, use `adb reverse` for provider ports so the exact localhost issuer in discovery matches Flutter/backend validation. The API alone may use `10.0.2.2`; see [android-networking.md](android-networking.md).

## Start and stop

From PowerShell, run one provider at a time or both independently:

```powershell
.\docs\identity\poc\Start-IdentityPoc.ps1 -Provider keycloak
.\docs\identity\poc\Start-IdentityPoc.ps1 -Provider zitadel
.\docs\identity\poc\Stop-IdentityPoc.ps1 -Provider keycloak
```

The start script generates high-entropy local admin/database/bootstrap passwords on first run and writes them to each provider's ignored `.env`. It never prints their values. Treat these as disposable local secrets. To reset all synthetic state use `-RemoveLocalData` when stopping. Do not expose either stack to a LAN or internet; HTTP is intentionally local and insecure.

Verify OIDC discovery/JWKS for both running stacks with `./docs/identity/poc/Test-IdentityPoc.ps1`; use `-Provider keycloak` or `-Provider zitadel` to check one.

## Provider setup

- [Keycloak setup](keycloak-setup.md): realm import creates the native public client, API audience, POC scope and basic roles. Create a synthetic user from the admin console.
- [ZITADEL setup](zitadel-setup.md): create the equivalent project, API role/audience and Native PKCE app after the local instance initializes.

No initial password or personal test identity is committed. Use an `.test` email or local username and a unique random password for every ephemeral test account. Do not enable external social login, SMS, email sending or external IdPs.

## Backend POC profile

The backend's production JWT decoder rejects HTTP issuers by default. For these local containers, run with the explicit Spring profile `identity-poc` and `POC_ALLOW_HTTP_ISSUER=true`; the code accepts HTTP only for `localhost`/`*.localhost`/loopback addresses in that profile. The profile adds `/api/v1/poc/whoami`, requiring the POC scope. Normal profiles and every other route keep existing behavior. Never set the POC profile/flag in production.

```powershell
$env:SPRING_PROFILES_ACTIVE = 'identity-poc'
$env:POC_ALLOW_HTTP_ISSUER = 'true'
$env:OIDC_ISSUER_URI = 'http://localhost:8180/realms/kunde-dev'
$env:OIDC_AUDIENCE = 'kunde-api'
Push-Location backend
mvn spring-boot:run
Pop-Location
```

For ZITADEL, set `OIDC_ISSUER_URI=http://localhost:8280`, `OIDC_AUDIENCE` to the POC project ID and `POC_ZITADEL_ORGANIZATION_ID` to the development organization ID. The launcher prompts for these IDs. See [ZITADEL setup](zitadel-setup.md) for the signed role claim contract.

The Windows Java TLS fix and exact Maven `verify` steps are documented in [maven-tls.md](maven-tls.md). `Initialize-MavenTrust.ps1` derives a local truststore only from a certificate chain already validated by Windows; no certificate-check bypass is used.

## Flutter POC

The app includes an opt-in screen behind `IDENTITY_POC_ENABLED=true`. It uses AppAuth's Authorization Code + PKCE flow, OS browser and secure storage. Build/run it only with local provider values; no client secret exists in the mobile app. Configure exact issuer, client ID, redirect and scope list following each provider guide. Local cleartext traffic is restricted to the Android debug manifest; release manifest remains HTTPS-only. The POC intentionally does not implement production registration, phone OTP or final UX.

## Data and safety

The stacks use isolated local PostgreSQL volumes. Test user credentials, access/refresh tokens and service state are local and disposable. For Android Emulator, run `adb reverse tcp:8280 tcp:8280` and `adb reverse tcp:8080 tcp:8080` so its loopback URLs reach the host. Do not attach a real account, use production tokens, add real contact details, or connect an SMS/WhatsApp service. ZITADEL Compose mounts the Docker socket read-only for its local Traefik discovery; keep this POC local and remove it when finished.
