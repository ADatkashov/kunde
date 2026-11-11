# KUNDE project state

Reviewed2026-11-11 against GitHub, not recovered Codex filesystem.

## Source and architecture

Public repository [ADatkashov/kunde](https://github.com/ADatkashov/kunde).
Main baseline5c3291a; CI migration on branch ci/github-hosted-migration-20261111,
[draft PR1](https://github.com/ADatkashov/kunde/pull/1), not merged.
Published backend remains Java21/Boot3.5.7/JDBC/PostgreSQL/FlywayV1. Flutter3.47
contains Consumer shell and opt-in system-browser AppAuth PKCE POC.
Existing EP-001/POC evidence preserved; no production readiness.

Missing from discovered remote baseline: cloud-only identity V2/canonical accounts/
profile module, abuse controls, Boot4/ADR016 migration and native runner. Previous
48/24-test/zero-vulnerability claims do not establish this repository's state.
No recovery or recreation of those implementations is claimed by this CI change.

## Hosted CI and open work

Primary build target is standard free GitHub-hosted Ubuntu24.04, Java21,
repository-compatible Flutter3.47. No personal Windows or self-hosted dependency.
Independent backend/Flutter/APK/security/lightweight workflows; manual E2E checks
actual prerequisites/KVM and never fabricates authentication success.
KGP2.4.20 candidate applied with AGP9.1/Gradle9.3.1; verify actual APK/graph/OSV.
Resource probes use actual free disk, not a60GiB prerequisite. Measured hosted
worker4CPU/~16GB RAM/~86GiB free; no preinstalled tools deleted.

Backend and Flutter hosted CI pass. APK compilation passed, but strict graph found KGP2.2.10 despite declaration2.4.20. Explicit app plugin application is being verified. Flutter included-build older Kotlin exposure remains OPEN; no global GHSA closure.
OSV v2 actual baseline72 matches:10CRITICAL/27HIGH/26MODERATE/9LOW; build roots0.
Trivy0.76.2 scans immutable bases successfully but reports runtime2HIGH/56MEDIUM/
4LOW and build18HIGH/610MEDIUM/179LOW; raw exit10 each, jobs fail on findings.
Gitleaks8.30.1 full-history redacted scan passes. Native E2E NOT_EXECUTED because
published Consumer profile/isolated native scenario scripts are missing.

TASK-003 partially_verified; TASK-006 and TASK-046 in_progress.
[CI/security/coverage/artifact contract](docs/engineering-foundation/github-hosted-ci.md),
[vulnerability ledger](docs/security/ci-vulnerability-ledger.md).
No force push, main merge, branch-protection change, production deployment or risk acceptance.
