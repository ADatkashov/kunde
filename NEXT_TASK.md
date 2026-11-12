# Next task — complete TASK-046 foundation abuse controls

Continue the existing TASK-046 security work before advancing dependent pilot
features. See docs/security/TASK-046.md and the vulnerability ledger for scope.
The per-process peer-IP quota increment needs current-head hosted verification;
account/device/edge quotas, request-body size controls and the upstream Flutter
SDK GHSA-r937 finding remain open. Do not suppress the audit or patch SDK sources.

Acceptance for the quota increment: allowed requests retain current behavior;
exhaustion and active-table capacity return correlated 429 with Retry-After;
spoofed forwarding headers do not bypass limits; health probes remain available;
concurrent admission stays bounded. Run backend `mvn clean verify`, packaged JAR
smoke and the hosted configuration/backend/security workflows. Keep TASK-046
in_progress and record remaining production/owner gates explicitly.

TASK-006 Consumer native E2E remains the following identity verification step:
use docs/identity/consumer-validation/README.md and implement the missing isolated
native scenario before claiming Android/iOS browser, vault or accessibility passes.
