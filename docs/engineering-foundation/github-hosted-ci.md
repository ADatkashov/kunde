# GitHub-hosted CI/CD migration 1.0

KUNDE uses standard free GitHub-hosted Ubuntu24.04 runners as the primary
verification target. No Windows workstation, persistent agent, self-hosted runner,
paid larger runner, production deployment or branch-protection change is required.
Work is proposed on ci/github-hosted-migration-20261111, PR1; main is not merged.

## Remote source discovery

Base main5c3291a102b1ff882d06d944f885827fbdb0996a contains Boot3.5.7, Flutter3.47
POC, AGP9.1.0/Gradle9.3.1/KGP2.4.0, V1 and Foundation CI. Previous cloud-only
61 staged blobs, identity V2/account/profile module, abuse controls, Boot4/ADR016,
scanner/native runner implementation are NOT in this base. They were not recovered
or fabricated. Earlier48/24 tests and zero-finding graph claims do not describe
this published baseline. Existing POC evidence is preserved.

## Independent workflows

| Workflow | Scope |
|---|---|
| ci.yml | Lightweight YAML/Python syntax, whitespace and bounded tracked-file secret markers |
| backend.yml | Java21, Maven cache, synthetic PostgreSQL16, clean verify, executable JAR check, XML reports |
| flutter.yml | Flutter3.47.0, enforced lockfile, analyzer, formatter, machine-readable tests |
| android-apk.yml | Actual disk probes, heap3GiB/metaspace1GiB/workers2, single x64 debug APK, Gradle help/resolved graph, actual-graph OSV |
| security.yml | Resolved Maven/Pub, effective Maven plugin/AGP/KGP roots, Gitleaks8.30.1, Trivy0.76.2 immutable linux/amd64 base-image OS scans |
| android-e2e.yml | Manual-only prerequisites, KVM/resource check, isolated stack contract and hosted API30 x86_64 emulator |

Actions are pinned to upstream immutable commit SHAs resolved from their release
refs. No pull_request_target, privileged fork checkout or production secrets.
Default contents:read, checkout credentials not persisted. Public PR code receives
no repository write permission. All jobs have timeouts and workflow/ref concurrency
cancellation. Public PR and main events avoid duplicate branch-push/PR runs.
Maven caching keys follow pom; Flutter/Gradle caches are not persisted/uploaded.

PostgreSQL's static synthetic_ci_only value is a disposable job-local test fixture,
never a production credential. Native fixture scripts, when implemented, must
generate synthetic accounts, mask secrets before use, avoid token/body logs and
produce only sanitized status reports.

## Resource-aware builds

No60GiB requirement. Actual free space is recorded before setup and again after
Flutter. Threshold5GiB before setup/4GiB before single-architecture APK and Trivy.
Exit78 means INFRASTRUCTURE_BLOCKED; genuine test/scanner errors retain their
distinct codes. Thresholds permit an attempt, not guaranteed success.
Measured first hosted container runner:4 CPU,16367524KiB RAM,154894188544-byte
filesystem,92131721216 bytes free. This point-in-time measurement is not a promise
about all standard runners; GitHub advertises14GB SSD allocation. No global tools,
SDKs or user data were removed. If capacity fails, record report and try reduced
architecture/included artifacts or another standard free runner, never paid fallback.

## Kotlin

Change only KGP2.4.0 -> stable2.4.20; retain AGP9.1.0, Gradle9.3.1, Java21 and
repository Flutter3.47. Built-in Kotlin/new-DSL opt-out flags remain unchanged.
[Advisory](https://github.com/advisories/GHSA-r937-wjx7-w2jp):
before2.4.20 unsafe build-cache metadata deserialization; first listed prerelease
patch2.4.20-Beta1, stable candidate2.4.20 selected.
[Kotlin supported matrix](https://kotlinlang.org/docs/gradle-configure-project.html),
[AGP9.1 requirements](https://developer.android.com/build/releases/agp-9-1-0-release-notes),
[Gradle Java matrix](https://docs.gradle.org/9.3.1/userguide/compatibility.html)
and [Flutter Kotlin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
are authoritative references. KGP matrix supports Gradle7.6.3–9.7 and AGP8.5.2–9.3.1
for2.4.20; Gradle9.3.1 runs Java21. Matrix evidence does not replace app compilation.
Actual Gradle task requires exclusively2.4.20 in observed resolved KGP artifacts;
OSV scans app debug compile/runtime and visible project buildscript classpaths.
Included Flutter/plugin builds not observed in that graph remain a stated gap.
Final remediation status depends on actual run evidence, not this declaration.

## Scanner contract and coverage

OSV repository audit v2 uses public batch API and per-advisory details, retains
graph hashes/query UTC/advisory modified times.0=no known findings in scope,
1=findings,2=incomplete/unavailable. No immutable global DB snapshot supplied.
Resolved test/transitive Maven and hosted Pub are included; SDK placeholders excluded.
Effective build roots are not equivalent to all plugin transitive dependencies.
No advisory suppressions or accepted CRITICAL risks.

Trivy binary official release checksum verified. Tag manifests resolve to recorded
index/platform digests; scans use immutable platform reference. Exit10=findings,
other nonzero=scan/infrastructure error; raw image codes retained even if job fails.
DB metadata/version, digest, OS package findings and summaries are artifacts.
OS-only scans do not certify JDK tarball/runtime, Flutter/Dart engine, Android
SDK/NDK/native binaries, Gradle distribution or built application images.
Gitleaks CLI scans Git history with full redaction; bounded source marker check
provides additional lightweight coverage, not complete secret certification.

## Native identity E2E boundary

Manual workflow checks for Consumer MeController and real isolated-stack/native
scenario scripts. These do not exist in the discovered remote baseline, so it
reports BLOCKED_MISSING_IMPLEMENTATION/NOT_EXECUTED and skips emulator execution.
It does not build an insecure replacement password form or fake successful login.
Future scripts must exercise hosted Keycloak PKCE/login, JWT verification, UUID/
profile provisioning, restart/restore, serialized refresh, logout/relogin and
UUID/profile continuity; invalid token/account/ownership cases are also required.
Check /dev/kvm permissions before emulator setup; unavailable KVM is a blocker.
A bootstrap prerequisite success or APK is never native E2E success.
Manual workflows may require publication on default branch before dispatch is
available; no merge into main is authorized during this migration.

## Artifacts and cleanup

Debug x64 APK retained1 day, machine/XML/security/resource reports3 days, redacted
secret audit1 day. Upload only required files: no caches, database contents,
truststores, fixture credentials, token logs, screenshots of credential forms or
production keys. Reports do not imply unlimited public artifact quota.
Artifacts expire automatically; maintainers may delete old run artifacts through
Actions UI/API. No destructive cleanup or repository-wide deletion job configured.
Runner-local caches/database layers disappear with the ephemeral VM.
JAR packaging is verified; no duplicate JAR binary uploaded by default.

## Execution and review

Open PR checks are actual GitHub Actions runs, not Codex-local checks. No attempt
was made to recover the unavailable Codex workspace. See the dated security ledger
and PROJECT_STATE for exact URLs/conclusions. Merge requires owner review; this PR
does not enable production deployment, release signing or required merge gates.

## Verification evidence and known configuration corrections

[PR1 checks](https://github.com/ADatkashov/kunde/pull/1/checks) are the canonical
latest-commit results. Completed backend run43026317816 and Flutter43026318219
passed. Security43026318118 executed all audits; dependency/container jobs fail
for findings while secrets passes. APK run43026317991 compiled the x64 APK, then
the legacy resolvedArtifacts export failed due to ambiguous Flutter project
artifact variants. The subsequent commit uses ResolutionResult ModuleComponentIdentifier,
rejects unresolved dependencies and verifies exclusive KGP2.4.20. That exporter
correction must pass a real subsequent run before final Kotlin verification.
Initial Android workflow runner.temp job-env expression was also corrected.
No failed run is erased or described as a pass.

Scanner artifacts are accessible from the linked run pages for1–3 days; durable
summary findings remain in the ledger. Native manual workflow is deliberately
blocked until real missing implementation/scenario scripts are present.

Actual-resolution guard caught selected KGP2.2.10 after a clean declared2.4.20
scan. Explicit app Kotlin plugin application is added before Flutter. Upstream
Flutter included-build Kotlin2.2.20/KGP2.0.0 exposure remains separately OPEN;
project plugin remediation cannot certify the entire SDK toolchain.

AGP runtime classpaths require explicit patched buildscript dependency alignment,
not only settings or app plugin declarations. A pre-build strict component check
verifies the actual graph; the native vulnerability audit is an independent job,
so compile success and security findings have separate conclusions. The initial
full native graph found11 advisory/package matches including KGP2.2.10 and two
Bouncy Castle CRITICAL matches. These remain visible in the ledger.
