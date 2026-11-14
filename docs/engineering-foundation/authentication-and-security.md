# Authentication & Security

> **2026-11-14:** ADR-015 was amended by owner decision: authentication is the own phone-OTP implementation (`/api/v1/auth/*`), not an external OIDC provider. See [phone-otp-auth.md](../identity/phone-otp-auth.md). The OIDC/Keycloak text below is historical for the POC and the still-present, disabled-by-default OIDC resource-server mode.

Current foundation baseline: main `bb5619b`, including merged PRs #11–#12.
ADR-013 accepts the reversible fail-closed resource-server boundary; ADR-015 accepts
Keycloak primary/ZITADEL fallback for synthetic development. Neither approves a
production deployment, residency/processor terms, OTP delivery or operating owners.

The API validates configured issuer, audience, signature, timestamps and required
claims; it does not issue credentials or refresh tokens. Flutter uses real AppAuth
Authorization Code + PKCE and secure storage when explicitly enabled. Consumer
identity/profile owns its canonical UUID, unique issuer/subject binding, lifecycle
restrictions and optimistic profile updates. Session administration remains503.
Public catalog/search remain empty foundation responses. Actuator exposes health
only, with hidden details; no marketplace or money flow is enabled by this review.

## TASK-045 technical review and evidence

Verdict: **partially_verified**. The earlier claim that backend build/security
verification has not run is superseded. The current main's hosted Backend
[43188676123](https://github.com/ADatkashov/kunde/actions/runs/43188676123) passed 57
Java 21/PostgreSQL16 tests and packaged HTTP smoke. Its Security
[43188676100](https://github.com/ADatkashov/kunde/actions/runs/43188676100) passed
application dependency, container and secret jobs; SDK tooling still failed.
This is technical evidence, not a completed legal/privacy or production review.

| Risk / requirement | Enforced baseline and executable evidence | Remaining boundary |
|---|---|---|
| Fail-open identity / configuration | No-issuer protected503; HTTPS/loopback/profile and mandatory audience checks; SecurityConfigurationTest and PlatformMigrationIntegrationTest | Real production issuer/environment approval |
| Forged or confused JWT | Actual RSA/JWKS HTTP tests reject wrong signature/issuer/audience/time, absent required claims and symmetric-algorithm confusion; key rotation/cache cases pass | Live provider/native/device and operational key drills |
| Privilege escalation / identity aliasing | ConsumerAccessPolicy and ConsumerIdentityIntegrationTest cover malformed client/scope/type, restrictions, IDOR route denial, unique binding and concurrent provisioning | Full business-role/admin and account-linking policies |
| Data mutation / duplicate effects | Profile validation/optimistic concurrency tests; Flyway V1/V2 constraints and repeat migration | Approved domain migrations, retention and recovery owners |
| Logs / response disclosure | Correlation input validation, safe ApiError, sanitized unexpected exception logging and strict untrusted CORS tests | Production log/telemetry processor, retention and access review |
| Resource exhaustion | Bounded peer-IP429 and actual-stream413 controls from PRs #11–#12; concurrency, encoded-path, CORS and chunked JAR smoke | Verified identity/device/edge quotas and upload/concurrency budgets |
| Supply chain | Current hosted dependency/container/secrets jobs execute without suppression | SDK GHSA-r937 and binary/distribution coverage gaps |
| Personal-data location / processing | Synthetic-development boundary and existing identity privacy checklist | Counsel/processor/residency/retention approvals remain open |

The separate TASK-046 branch adds a post-JWT `(issuer, subject)` quota and tests it
with local signed-RSA/JWKS HTTP, not a permissive mock decoder. The initial main
reproduction returned 200 after the configured identity budget was exhausted.
Final local clean verify passes 68 tests with no failures/skips, including all
existing negative guards; packaged no-issuer/body smoke passes. Current-head
hosted results belong in that PR. The quota adds no schema, vendor or identity-link
behavior. Its key remains a verified external identity, not a replacement for the
KUNDE account UUID. Existing authorization still decides business access.

Read [TASK-046](../security/TASK-046.md), the [identity threat model](../identity/security-threat-model.md),
[privacy questions](../identity/privacy-and-compliance.md) and
[security ledger](../security/ci-vulnerability-ledger.md) for open controls.
TASK-045 is not promoted to implemented_verified; TASK-046/006 remain in_progress.
No risk finding, provider approval or production readiness is inferred from a test.
