# TASK-046 — API abuse and vulnerability controls

Status: **in_progress**. Production readiness: not approved.

This increment remediates the actual published dependency baseline, not missing Cloud-only identity/abuse code. See [ledger](ci-vulnerability-ledger.md), [runbook](security-runbook.md) and [ADR-016](../architecture/adr/ADR-016-supported-spring-boot-4-security-migration.md).

Implemented: supported Boot 4 BOM migration, malformed/signature-algorithm JWT regression, strict untrusted CORS denial, production/POC isolation, sanitized exception logging, actual native ownership graph and buildscript security constraints, SDK tooling audit, maintained immutable container candidates and effective-image verification.

Verified project native graph: run 43043575387 produced and signature-verified APK; independent OSV exit 0 / zero findings. Keep KGP 2.4.20 with AGP 9.1.1 / Gradle 9.3.1 / Java21 / Flutter3.47. Buildscript constraints: BC provider1.85.2, pkix/util1.85 (same published1.85 maintenance family), Guava33.7.2-jre, commons-lang3 3.18.0, jose4j0.9.6, JDOM2.0.6.1. These replace actual vulnerable versions; no force or SDK source patches.

Remaining gates: Flutter SDK older KGP advisory, coverage gaps, published API abuse/rate/size controls not implemented, owner review. TASK-006 remains in_progress: canonical account/profile/V2 and native Consumer E2E are outside this remediation; historical POC is not Consumer E2E.


### Main integration review — 2026-11-11

Main22c1ae8 now publishes Consumer canonical identity/profile, issuer/subject binding, FlywayV2, Consumer authorization and Flutter auth repository/tests. Earlier statements that these modules were absent describe the historical baseline only. Preserve these additions; do not replace them with the older branch. Owner explicitly authorized integration/merge through PR4. Combined-source checks are required; native Consumer E2E and API abuse controls remain open. TASK-006/TASK-046 stay in_progress; no production readiness.
