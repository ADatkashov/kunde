# Security verification and response runbook

Run GitHub-hosted Backend CI, Flutter CI, Android APK CI and Security CI. Run Container build and security verification for Dockerfile changes. Use Java 21 and pinned Flutter 3.47.0, Gradle 9.3.1, AGP 9.1.1, KGP 2.4.20. Inspect actual free capacity before downloads. No personal host or self-hosted runner is required.

Commands and coverage:
- Backend: `cd backend && mvn -B -ntp clean verify`; package smoke: `python3 scripts/ci/smoke_backend.py`, with synthetic PostgreSQL.
- Actual Maven/Pub graphs and effective BOM: commands in `.github/workflows/security.yml`; `osv_audit.py` checks resolved coordinates and declared build roots separately.
- Android: strict `android_graph.init.gradle` exports buildscript/compile/runtime ownership and representative shortest paths before compilation. Audit the resulting graph with OSV; inspect APK DEX and verify debug signature. Buildscript maintenance constraints do not modify SDK internals or add runtime dependencies.
- SDK: independent unmodified Flutter tooling graph, ephemeral Gradle home, no cache restore; audit separately. Project KGP success does not close SDK GHSA-r937-wjx7-w2jp.
- Containers: immutable bases via `resolve_images.py`; `container_effective.py` builds both effective stages, inventories recognized OS packages, scans with Trivy and performs runtime HTTP smoke.
- Secrets: checksum-verified Gitleaks full history with 100% redaction. Never upload credentials, raw JWTs, local truststores or database contents.

OSV exit 0 = no known findings in observed scope; 1 = findings; 2 = incomplete/unverified. Trivy raw exit 10 = findings, other nonzero = incomplete/error; preserve per-image JSON/exit codes. Never infer safety from unavailable databases or skipped jobs. Record scanner version, database timestamps where available, advisory modified times and image digest. No suppression to make CI green.

For a new advisory: identify package/version/path/owning execution context, authoritative affected/fixed ranges and supported BOM/vendor patch. Test negative security behavior and packaging before closing the finding. Absence of a currently exposed path is mitigation, not a fix. Keep actionable CRITICAL/HIGH open until fixed or explicitly dispositioned by owners. No risk is accepted by this runbook.

Artifacts: APK one day, normal reports three days, investigation ledgers 14 days; retain sanitized findings/run URLs in source. Do not store Gradle caches as artifacts. Effective local image IDs and archive hashes are immutable evidence, not published registry digests. Maven distribution embedded libraries, JDK native code, Flutter/Dart SDK binaries, Android SDK/NDK and host OS need additional coverage; OS scans do not certify them.

PR #1 was externally merged on 2026-11-11 at 15:41:52Z. Later remediation commits remain on the existing branch and require a new reviewed delivery; no reopening/merge or main write is performed by these checks.
