# 20 — CI/CD and Environments

## Pipeline stages

1. Pull request: formatting/lint, module-boundary check, unit tests, secret/dependency scan, API/schema compatibility check.
2. Build: reproducible versioned container/mobile artifact, SBOM, signature and provenance.
3. Integration: ephemeral or isolated test DB, migrations from empty and previous schema, contract tests, outbox/idempotency tests.
4. Staging: deploy immutable artifact, smoke/API/mobile checks, synthetic payment provider, no production credentials or real PII.
5. Release approval: change summary, migration/rollback plan, security findings, feature flags, owner/on-call readiness.
6. Production: progressive rollout, health gates, error/financial-integrity monitoring, automatic halt/rollback on defined thresholds.

## Environments/secrets

Separate dev/test/staging/prod identity, DB, keys and provider sandboxes. Secret values are injected from managed secret storage at runtime, never committed or embedded in mobile builds. Least-privilege CI identity uses short-lived federation where supported. Production access is approval-bound and audited.

## Database migrations

Migration is backward-compatible with currently deployed and next app version. No destructive change in same release as usage removal. Large backfill is idempotent, chunked, observable and resumable; write pause is explicit if necessary. Migration failure halts promotion; rollback restores compatible app/schema state, not destructive DB rollback.

## Mobile release

Build signed iOS/Android artifacts from controlled CI, protect signing keys, use staged rollout/store phased release where available, API compatibility checks and remote kill switches for risky integrations. Store submission and app review are explicit release steps; rollback may require forward release, so server-side feature flags and backward-compatible APIs matter.
