# Consumer Identity verification, 2026-11-11

Development evidence only. ADR-015 authorizes synthetic development with
Keycloak; production privacy, residency, operations, OTP and recovery gates remain.

## Automated checks

Java 21, Spring Boot **4.0.9** (actual pom), PostgreSQL 16.15 and Flyway V1/V2:
`mvn --batch-mode --no-transfer-progress clean verify` passed 40 tests, no skips.
The suite covers concurrent provisioning and profile updates, unique binding,
restricted users, IDOR route rejection, validation and optimistic locking, real
RSA signatures/JWKS rotation, issuer/audience/time/required claims (including raw signed subject type) and consumer
scope/client/type checks. Mock-decoder tests exercise malformed claim shapes;
signed-token HTTP tests independently exercise the real security filter chain.

Flutter 3.47.0: `flutter pub get --enforce-lockfile`,
`flutter analyze --fatal-infos`,
`dart format --output=none --set-exit-if-changed lib test`, and `flutter test`.
33 tests passed, including browser gateway parameters, serialized refresh/logout,
restore, issuer context isolation, 401/403/409, offline recovery, route boundary,
editing/discard, registration, locales and a phone-size welcome golden.
Golden fonts come from the pinned Flutter SDK, not host-installed fonts.

The packaged JAR smoke passed health 200, OpenAPI 200 and protected-route 503
without issuer. The premium UI static audit found no violations; it does not
establish native accessibility or provider callback behavior.

## Real Keycloak protocol check

`verify.py` uses only Python standard-library HTTP/cookie/form support. It is
hardcoded to loopback and creates a fresh synthetic account with an ephemeral
password; no credentials/tokens are printed or saved. It does **not** launch
Flutter, Chrome Custom Tabs or an iOS authentication session. Local cookie policy
matches a browser's secure-localhost exception for the isolated HTTP POC.

Start a **fresh isolated** Keycloak 26.8.2 development installation with
`realm.json` in `data/import/`:

```sh
bin/kc.sh start-dev --http-host=127.0.0.1 --http-port=8180 --import-realm
```

Use a disposable PostgreSQL database for backend validation. Start the verified
JAR with `PORT=8081`, `CONSUMER_IDENTITY_ENABLED=true`,
`OIDC_ISSUER_URI=http://localhost:8180/realms/kunde-consumer-check`,
`OIDC_AUDIENCE=kunde-api`, `SPRING_PROFILES_ACTIVE=identity-poc`,
`POC_ALLOW_HTTP_ISSUER=true`, and the database connection variables.
Run `python3 docs/identity/consumer-validation/verify.py`.
Never import this HTTP/synthetic realm into production. Import skips an existing
realm; changing the fixture does not change an already-running realm.

Observed using the real provider and packaged API: registration returned an
OIDC code with matching state; S256 code exchange succeeded; issued access token
passed backend signature/issuer/audience/consumer policy; GET and PATCH /me
returned 200; stale PATCH returned 409; refresh rotated; replay returned 400.
Provider logout returned 204 and rejected subsequent refresh with 400. A new
browser-protocol authorization displayed the credential form and login succeeded.
The check re-ran successfully with fresh synthetic users.

This is HTTP protocol evidence, **not native E2E**. Native Android/iOS browser
callback, device secure storage, accessibility and release signing remain to be
verified on supported devices. Session-administration endpoints still explicitly
return 503; the app does not advertise them. JWTs remain accepted after provider
logout until their expiration plus Spring's 60-second tolerance, while restricted
KUNDE accounts are denied on every profile operation.

## Configuration for mobile development

```sh
flutter run --dart-define=CONSUMER_IDENTITY_ENABLED=true \
  --dart-define=OIDC_ISSUER_URI=https://identity.example.test/realms/kunde \
  --dart-define=OIDC_CLIENT_ID=kunde-consumer \
  --dart-define=API_BASE_URL=https://api.example.test/api/v1/
```

Replace example hosts with the development deployment. Public native client:
Authorization Code only, PKCE S256 required, no client secret/password grant,
exact redirect and post-logout URI `com.kunde.mobile:/oauth2redirect`, basic
subject mapper, profile and `kunde.consumer` scopes, access-token audience
`kunde-api`. Enable registration in the development realm to expose its real
registration form. The app uses Keycloak's `/registrations` endpoint with native
AppAuth code exchange. Access lifespan 300s, refresh rotation Max Reuse 0, idle
1800s, max session 43200s. HTTPS is required outside loopback debug POC.
For Android loopback issuer, use adb reverse as in the existing POC guide; do not
replace the issuer host with emulator IP. API debug traffic may use 10.0.2.2.

Access tokens remain in memory. The refresh/id-token set resides in the platform
secure vault, bound to issuer/client/API configuration. iOS uses unlocked,
this-device-only keychain accessibility; Android backup is disabled. V1 stored
sessions are intentionally invalidated once when upgrading to the contextual V2
record. Temporary provider failures keep the refresh token for explicit retry;
invalid_grant clears it. A lost rotation response can require sign-in again when
Keycloak rejects the retry; this is safer than relaxing refresh replay policy.

## Native Android Consumer scenario — TASK-006

The manual `Android identity E2E` workflow builds a Consumer-enabled debug APK
against a fresh loopback fixture and runs the real application and Chrome on an
Android 35 x86_64 emulator with KVM. Its scripts refuse physical devices. Each job
creates a synthetic seed account, disposable PostgreSQL/Keycloak services and the
real backend. Private fixture credentials and logs stay in runner temporary storage;
cleanup stops only the marked containers and backend process. No production setup
or password-grant flow is introduced.

Start the manual workflow on the reviewed branch. Its six targeted checks are:

- RU/KK/EN welcome labels.
- Chrome credential login, PKCE callback and verified API profile.
- Native profile edit persisted under the canonical KUNDE UUID.
- Two process restarts with secure-vault restore and rotated refresh persistence.
- API offline state and retry without account loss.
- Provider logout, subsequent credential form and same-account relogin.

Only `e2e-status.json` and a verified application profile screenshot may be
uploaded, with three-day retention. Raw UI XML, browser screenshots, authorization
URLs, passwords and tokens are excluded. Failure diagnostics expose only fixed
label/package/resource-ID allowlists and counts. The workflow fails unless all six
checks execute successfully; a successful fixture/bootstrap is insufficient.
Even a passing run reports `EXECUTED_PARTIAL`: registration, native replay capture,
provider outage, expiry, iOS, TalkBack, large text, full RU/KK profile journeys and
physical devices remain explicitly unverified. TASK-006 stays `in_progress`, and
session administration still returns 503.

Observed hosted diagnosis:
[run 43204760791](https://github.com/ADatkashov/kunde/actions/runs/43204760791),
source `caa144c`, built and signed the Consumer debug APK and passed native
RU/KK/EN welcome checks. It failed at system-browser login: both device loopback
HTTP probes returned 200 and Chrome had a fixture page without reported network
errors, but UIAutomator exposed only Chrome controls, without credential fields.
This run does not verify native login, callback, vault restore or logout. Run [43206220374](https://github.com/ADatkashov/kunde/actions/runs/43206220374),
source `bfa1c34`, reproduced that failure with forced renderer accessibility.
The harness now uses DevTools for the real browser form and ADB for the Flutter UI.
Browser accessibility remains unverified.

The DevTools adapter checks the exact fixture origin/realm before entering synthetic
credentials, submits the real Keycloak form and requires the native callback and
verified API response. It does not intercept OAuth or fabricate tokens. Its only
Python dependency, `websocket-client==1.9.2`, is wheel-hash pinned, installed into a
job-local virtual environment without dependencies and included in the existing
Security CI OSV graph audit. Fourteen local Python tests pass, including hostile
origin rejection, unavailable-form refusal, safe errors and fail-closed audit input.
An independent disposable Cloud Chromium check passed real form submission, S256
code exchange and protected `/me` 200 using source `94de27c`; this establishes the
browser adapter boundary, not Android callback/vault behavior. Owned services and
the temporary browser profile were stopped afterwards.

DOM diagnosis in [run 43208441308](https://github.com/ADatkashov/kunde/actions/runs/43208441308),
source `94de27c`, established that the Android 30 browser reached a Keycloak
`Cookie not found` error page with zero inputs. Device HTTP probes still returned
200. The earlier missing fields were therefore insufficient evidence of an
accessibility-only defect. The workflow now targets Android 35 and records actual
Chrome/API versions, preserving provider cookie/security settings. Browser form
submission carries DevTools user-gesture semantics for native custom-scheme
redirects. Its successful hosted evidence is recorded below.

### Successful limited native run

[Run 43209945677](https://github.com/ADatkashov/kunde/actions/runs/43209945677),
source `db13a26f8af7a3d85e14e311387618400807d970`, succeeded on **Android API35,
Chrome124.0.6367.219**, with provider cookie settings retained. All six targeted
checks listed above passed, including the actual AppAuth callback and two
vault-backed restores under refresh Max Reuse0. The evidence-check step and owned
fixture cleanup also succeeded. The downloaded artifact contains only the scoped
status report and verified profile screenshot; both were inspected. A permanent
[sanitized report snapshot](native-evidence-2026-11-12.json) records the source/run,
completed and unexecuted checks, environment and screenshot digest. The workflow
artifact has three-day retention.

This is `PASSED_EXECUTED_SCENARIOS` / `EXECUTED_PARTIAL`, not complete TASK-006 DoD.
Native registration/replay/outage/expiry, iOS, TalkBack, large text, full RU/KK
profile journeys, physical devices and session administration remain open. The
next existing-backlog action is native registration verification under TASK-006.
