# Next task: complete equivalent ZITADEL identity POC

**Priority:** continue EP-002 POC with synthetic data. Keep provider selection open; do not implement production login/session APIs or change security policy before decision approval.

## Already done

- Keycloak 26.8.2 Android system-browser Authorization Code + PKCE, callback/code exchange, real JWT validation and protected Spring API HTTP 200 passed.
- Keycloak refresh succeeded; logout produced a fresh login prompt on the next authorization.
- ZITADEL 4.19.5 API, login UI, PostgreSQL and proxy were healthy; OIDC discovery endpoints responded. Native app/project/user are not configured.
- Evidence is indexed in [`docs/identity/poc/test-results.md`](docs/identity/poc/test-results.md) and [`end-to-end-evidence.md`](docs/identity/poc/end-to-end-evidence.md).

## Actions

1. Read [`AGENTS.md`](AGENTS.md), [`PROJECT_STATE.md`](PROJECT_STATE.md), [`docs/identity/poc/README.md`](docs/identity/poc/README.md), [`zitadel-setup.md`](docs/identity/poc/zitadel-setup.md), [`android-networking.md`](docs/identity/poc/android-networking.md), [`provider-recommendation.md`](docs/identity/poc/provider-recommendation.md) and ADR-015.
2. Check `git status --short --branch`; if Git metadata is still absent, record that and preserve the supplied workspace without creating a repository.
3. Start only the isolated ZITADEL POC with `pwsh -NoProfile -File docs/identity/poc/Start-IdentityPoc.ps1 -Provider zitadel`; verify health/discovery/JWKS with `pwsh -NoProfile -File docs/identity/poc/Test-IdentityPoc.ps1 -Provider zitadel`.
4. In the local console, configure a synthetic development project, Native public OIDC application, exact redirect `com.kunde.mobile:/oauth2redirect`, PKCE S256, API audience and required project role scopes; create a synthetic `.test` user. Follow `zitadel-setup.md`; no client secret in Flutter.
5. Confirm discovery issuer consistency and use `adb reverse tcp:8280 tcp:8280` and `adb reverse tcp:8080 tcp:8080`. Start the backend with `pwsh -NoProfile -File docs/identity/poc/Start-BackendPoc.ps1 -Provider zitadel` in a separate terminal; use only loopback HTTP under the POC profile.
6. Build/run the Flutter identity POC with matching ZITADEL issuer/client/redirect/scopes; complete Chrome Custom Tab login, callback, token exchange and protected API call. Capture sanitized HTTP/status evidence, never token values.
7. Verify refresh and logout/relogin; then exercise available negative JWT/audience/scope and callback cases without weakening validation. Distinguish untested cases clearly.
8. Update identity result/evidence docs and ADR-015 evidence while leaving ADR-015 PROPOSED, TASK-005 blocked and TASK-006 not started. Do not mark EP-002 complete.

## Acceptance

- ZITADEL's real Android PKCE callback completes on the existing emulator.
- A ZITADEL real access token passes the configured strict Spring issuer/signature/audience/scope checks and the protected endpoint returns HTTP 200.
- Refresh and logout outcomes are observed and documented; all unrun scenarios remain explicitly marked.
- Provider comparison reflects equivalent evidence and keeps the decision proposed pending owner/legal/operations approval.

If console/client setup is blocked, record the exact step, error and evidence, then complete independent security/lifecycle checks for Keycloak. Do not call the cross-provider POC complete.

## Useful commands

Run PowerShell 7 from repository root. For Maven TLS/verification when code or dependencies change, see [`maven-tls.md`](docs/identity/poc/maven-tls.md); bootstrap with `. .\docs\identity\poc\Initialize-MavenTrust.ps1`, then run `mvn --batch-mode --no-transfer-progress verify` from `backend/` in that shell. Do not repeat expensive suites without a relevant change.

```powershell
pwsh -NoProfile -File docs/identity/poc/Start-IdentityPoc.ps1 -Provider zitadel
pwsh -NoProfile -File docs/identity/poc/Test-IdentityPoc.ps1 -Provider zitadel
adb devices
adb reverse tcp:8280 tcp:8280
adb reverse tcp:8080 tcp:8080
cd mobile
flutter analyze --fatal-infos
flutter test
```

For Flutter provider defines, API runtime, teardown and test-user setup, follow the linked POC docs rather than copying secrets or inventing client values here.
