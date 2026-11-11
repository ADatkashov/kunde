# Next task — finish hosted CI evidence, then remediate published security baseline

Read AGENTS.md, PROJECT_STATE.md, [CI contract](docs/engineering-foundation/github-hosted-ci.md)
and [ledger](docs/security/ci-vulnerability-ledger.md). GitHub is the source of truth.
Do not recover old Codex Cloud or require a personal Windows/self-hosted runner.

Review draft PR1 ci/github-hosted-migration-20261111; do not merge main without
owner authorization. Finish APK/Gradle2.4.20/OSV evidence before calling Kotlin fixed.
Backend/Flutter hosted checks pass. Security jobs correctly fail on genuine
published Boot3.5.7/container findings; no suppression or accepted CRITICAL risks.
Next engineering priority within TASK-046 is a supported, isolated-tested backend
BOM and vendor-base OS remediation using these actual hosted reports.

TASK-006 stays in_progress: canonical account/profile/V2 implementation and actual
native-browser E2E scripts were not published. Reimplement missing approved identity
foundation in a separate scoped change, then execute manual hosted Keycloak/PKCE/
JWT/profile/restart/refresh/logout/relogin scenario on real emulator with KVM.
An APK or fixture JWT test cannot satisfy this acceptance.

TASK-003 partially_verified until final hosted workflow evidence and review;
TASK-046 in_progress; no production readiness. Artifacts expire1–3 days, so preserve
sanitized summary evidence/run URLs in docs, never credentials/raw tokens/databases.
