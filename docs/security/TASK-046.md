# TASK-046 — API abuse and vulnerability controls

Status: **in_progress**. Production readiness: not approved.

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

Remaining gates: Flutter SDK older KGP advisory, coverage gaps, account/device/edge quotas and body-size controls not implemented, owner review. TASK-006 remains in_progress: canonical account/profile/V2 and native Consumer E2E are outside this remediation; historical POC is not Consumer E2E.


### Main integration review — 2026-11-11

Main22c1ae8 now publishes Consumer canonical identity/profile, issuer/subject binding, FlywayV2, Consumer authorization and Flutter auth repository/tests. Earlier statements that these modules were absent describe the historical baseline only. Preserve these additions; do not replace them with the older branch. Owner explicitly authorized integration/merge through PR4. Combined-source checks are required; native Consumer E2E and API abuse controls remain open. TASK-006/TASK-046 stay in_progress; no production readiness.
