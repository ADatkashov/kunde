# Next task — TASK-046 authenticated abuse controls

Finish reviewing/merging the bounded request-body increment, then continue the
existing TASK-046 account/device/edge quota scope. Keep peer-IP admission and body
bounds before expensive JWT/controller work; authenticated account keys must derive
from verified identity, never caller-supplied headers or unverified claims.
See docs/security/TASK-046.md for configuration, deployment limits and open gates.

Current body-limit acceptance: known and streamed excess returns safe correlated
413 before downstream effects; exact byte boundary and bounded UTF-8 JSON remain
intact; CORS and empty probes work; no more than limit+1 bytes are read. Cloud
clean verify passes 57 tests; require current-head hosted backend/configuration,
Flutter and security results plus packaged-JAR Content-Length/chunked smoke.

TASK-046 remains in_progress. SDK GHSA-r937, distributed edge/concurrency/read-timeout
controls, production thresholds and audit coverage are not closed by a local quota.
Do not suppress security failures or modify upstream SDK sources.

TASK-006 Consumer native verification follows the security prerequisites; implement
the isolated native scenario before claiming Android/iOS browser/vault/accessibility
acceptance. See docs/identity/consumer-validation/README.md.
