# TASK-046 — API abuse and vulnerability controls

Status: **in_progress**. Production readiness: not approved.

## Verified-identity quota increment — 2026-11-12

Current main bb5619b includes merged peer-IP and body guards (PRs #11–#12). This
increment adds a distinct per-process quota after Spring's bearer authentication
filter and before authorization/controllers in all security chains. It reads only
an authenticated `JwtAuthenticationToken` from SecurityContext, after signature,
exact issuer, audience and time checks. It does not parse Authorization or trust
client account/device headers. Unexpected missing issuer/subject fails closed 401.
Anonymous/rejected bearer calls do not allocate an identity quota.

The key is an immutable `(issuer, subject)` pair; token value, jti and peer IP are
not part of it. Token rotation and network changes therefore retain the budget,
while distinct issuers/subjects remain isolated. This is a verified external
identity budget, not canonical KUNDE UUID/alias linking. Existing business
authorization, account restrictions and identity ownership remain in their domain.

Defaults: 60 requests/60 seconds, 4096 identities per process. Configure
`API_AUTH_RATE_LIMIT_REQUESTS`, `API_AUTH_RATE_LIMIT_WINDOW_SECONDS` (1–3600),
`API_AUTH_RATE_LIMIT_MAX_IDENTITIES`; nonpositive values fail startup. Shared
`FixedWindowQuota` preserves the existing peer-IP algorithm: monotonic timing,
serialized admission, no eviction of active keys, lazy expiry and bounded entry
count. Full table or exhausted identity returns 429/RATE_LIMITED with positive
rounded-up Retry-After, no-store, correlation ID and existing CORS/security headers.
Health is excluded. The aggregate `kunde.api.authenticated_rate_limit.denied`
counter has no identity/token labels; neither keys nor bearer values are logged.
Keys are held only in bounded memory, removed on a later authenticated admission
after expiry or process exit; this is not an approved production retention policy.

Local signed-RSA/JWKS HTTP tests reproduced 200 instead of 429 before implementation.
They now verify rotated-token sharing, independent users, forged-signature 401
without victim quota consumption, anonymous isolation, encoded paths, safe CORS,
health and a shared budget across normal/POC chains. Unit tests cover changing
peers, structured key components, malformed principals, saturation, expiry,
configuration and concurrency. These fixtures are not live provider/native E2E.

Canonical account-wide budgets across linked IdP bindings, trusted device identity,
distributed edge/read-timeout/concurrency controls and production thresholds still
require their respective contracts/owners. No Redis, schema, vendor or linking
decision is introduced. TASK-046 and SDK GHSA-r937 remain open; the earlier owner
merge permissions for PRs #11–#12 did not close the finding or approve production.

## API body limit increment — 2026-11-12

`ApiBodyLimitFilter` runs after CORS and peer-IP rate admission, before JWT work
and controller execution in all three security chains. Servlet auto-registration
is disabled so each request is checked once. The servlet-decoded API path prevents
encoded-prefix bypass. `/api/v1` and descendants, including API health, are covered;
empty health probes remain available and Actuator is outside this API boundary.

`API_MAX_BODY_BYTES` defaults to 65536 bytes, with a hard configuration range of
1–1048576. Larger declared Content-Length is rejected without opening the input.
Otherwise the filter reads at most limit+1 bytes, independent of advertised length
or HTTP chunking, before any downstream handler can run. Overflow returns 413 /
`PAYLOAD_TOO_LARGE`, no-store and the existing safe correlated error envelope;
approved-origin CORS/security headers are preserved. Accepted bytes are buffered
and passed to the synchronous JSON parser unchanged. UTF-8 is counted in bytes.
The aggregate `kunde.api.body_limit.denied` counter has no identity/body labels;
bodies are neither persisted nor logged.

This is the boundary for the current synchronous JSON API. Form/multipart parsing,
nonblocking request streams, compressed-content expansion and upload endpoints
require separate contracts and verification before activation. The quota bounds
buffered bytes, not upload duration; production ingress read/idle timeouts,
connection/concurrency limits and equivalent edge limits remain owner gates.
The default is a foundation budget, not an approved production workload policy.

Acceptance evidence includes actual fixed-length and chunked HTTP requests,
encoded API paths, safe CORS errors, unchanged bounded JSON conversion and denied
authentication, plus unit tests for understated lengths, byte boundaries, reader
semantics, UTF-8, invalid configuration and limit+1 reads from an unbounded stream.
The initial real HTTP regression reproduced 200 instead of 413 on main5e8c182.
Actual final command/run results are recorded in implementation-status and the PR.
TASK-046 remains in_progress for account/device/edge controls, SDK and coverage gaps.

PR #11 peer-IP quota was merged as 5e8c182 after explicit owner permission to merge
with the known open GHSA-r937. That is a bounded merge exception; the vulnerability
is still open and production readiness is not approved.

## Per-process API quota increment — 2026-11-12

`ApiRateLimitFilter` runs inside the selected security chain, after correlation
assignment and CORS/header handling, before JWT verification. Servlet auto-registration
is disabled to avoid duplicate execution and preserve allowed-origin CORS on 429.
It limits `/api/v1` and descendants, except `/api/v1/health`, by transport peer IP.
Actuator probes are outside this quota. Servlet-decoded paths are used so an
encoded API prefix cannot bypass the quota. CORS preflights are handled by CORS
before quota admission. Defaults: 120 requests per 60-second fixed window, at most
4096 client entries per API process. Configuration:
`API_RATE_LIMIT_REQUESTS`, `API_RATE_LIMIT_WINDOW_SECONDS` (1–3600), and
`API_RATE_LIMIT_MAX_CLIENTS`; nonpositive values fail startup.

Exhausted quota or a full active client table returns 429 / `RATE_LIMITED`, a
positive rounded-up `Retry-After`, `Cache-Control: no-store`, `nosniff`, and the
existing correlated JSON error envelope. Active entries are not evicted to admit
new peers; expired entries are discarded lazily on subsequent API requests.
Admission is synchronized so concurrent requests cannot overspend the quota.
The aggregate `kunde.api.rate_limit.denied` counter has no IP/user/token labels.
Peer addresses exist only in the bounded in-memory table, without persistence or
logging; idle expired entries disappear on the next API request or process exit.

`server.forward-headers-strategy=none` is explicit: caller-controlled Forwarded
and X-Forwarded-For headers cannot create new quotas. Behind a reverse proxy, all
clients sharing a transport peer share its quota. Production ingress must supply
separately reviewed trusted-proxy/edge quotas before changing this setting.

This is a foundation control, not production abuse readiness. Fixed windows allow
bursts at window boundaries; process restart resets budgets and replicas each own
their quota. Account/device/operation quotas, distributed edge protection, body
size limits, production thresholds and SDK/native audit gaps remain open.
TASK-046 stays in_progress. No OTP/provider cost protection is inferred.

Verification: deterministic filter tests cover isolation, spoofed headers, expiry,
Retry-After rounding, bounded-table saturation, probes and concurrent admission.
A real embedded-server HTTP test covers filter order, the existing 503 denied
route, encoded-prefix bypass rejection, CORS/429 headers and health availability.
The encoded-prefix check reproduced 200 before using the servlet-decoded path;
the final complete Cloud suite passes 47 tests without failures or skips.
Execution results belong in the
PR and implementation-status evidence; this test list alone is not a pass claim.

This increment remediates the actual published dependency baseline, not missing Cloud-only identity/abuse code. See [ledger](ci-vulnerability-ledger.md), [runbook](security-runbook.md) and [ADR-016](../architecture/adr/ADR-016-supported-spring-boot-4-security-migration.md).

Implemented: supported Boot 4 BOM migration, malformed/signature-algorithm JWT regression, strict untrusted CORS denial, production/POC isolation, sanitized exception logging, actual native ownership graph and buildscript security constraints, SDK tooling audit, maintained immutable container candidates and effective-image verification.

Verified project native graph: run 43043575387 produced and signature-verified APK; independent OSV exit 0 / zero findings. Keep KGP 2.4.20 with AGP 9.1.1 / Gradle 9.3.1 / Java21 / Flutter3.47. Buildscript constraints: BC provider1.85.2, pkix/util1.85 (same published1.85 maintenance family), Guava33.7.2-jre, commons-lang3 3.18.0, jose4j0.9.6, JDOM2.0.6.1. These replace actual vulnerable versions; no force or SDK source patches.

Remaining gates: Flutter SDK older KGP advisory, coverage gaps, canonical account/device/edge quotas and production owner review. TASK-006 remains in_progress: canonical account/profile/V2 and native Consumer E2E are outside this remediation; historical POC is not Consumer E2E.


### Main integration review — 2026-11-11

Main22c1ae8 now publishes Consumer canonical identity/profile, issuer/subject binding, FlywayV2, Consumer authorization and Flutter auth repository/tests. Earlier statements that these modules were absent describe the historical baseline only. Preserve these additions; do not replace them with the older branch. Owner explicitly authorized integration/merge through PR4. Combined-source checks are required; native Consumer E2E and API abuse controls remain open. TASK-006/TASK-046 stay in_progress; no production readiness.
