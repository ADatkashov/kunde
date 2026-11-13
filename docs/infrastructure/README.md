# KUNDE infrastructure (portable IaC foundation)

**Status:** foundation only. Nothing is provisioned. No cloud provider, region, remote state or credentials exist; ADR-011/012/017 are *Proposed* and TASK-051 (hosting/residency gate) is blocked. Production readiness is not claimed.

## Architecture

```
backend/ (one Docker image) ──┐
infrastructure/modules/country-cell   provider-neutral contract (validates, creates nothing)
infrastructure/environments/kz/{dev,prod}   one root per cell, provider_id = "unselected"
infrastructure/providers/<id>   added only after a verified adapter (none yet)
infrastructure/helm/kunde-backend   only for Kubernetes cells
```

Separation: **country** (cell identity, residency), **environment**, **provider/region** (adapter), **secrets** (names in Git, values in a secret manager), **feature flags** (only flags the backend already reads: `CONSUMER_IDENTITY_ENABLED`; marketplace stays off in code, ADR-014).

## Audit (main at this commit)

| Item | Finding |
|---|---|
| Image | `backend/Dockerfile`: digest-pinned Java 21 UBI, non-root 10001, JVM `MaxRAMPercentage=75`. Reused unchanged. |
| Runtime config | `application.yml` env vars: `DB_URL/USERNAME/PASSWORD`, `OIDC_ISSUER_URI`, `OIDC_AUDIENCE`, `CORS_ALLOWED_ORIGINS`, `CONSUMER_IDENTITY_ENABLED`, `PORT`, rate-limit vars. |
| Health | Actuator `/actuator/health/liveness` and `/readiness` (readiness includes DB); graceful shutdown 20 s. |
| Migrations | Flyway runs at app start (V1–V8); validated in Backend CI against PostgreSQL 16. |
| CI | ci, backend, flutter, security, security-baseline, android/ios workflows. **No deploy job.** Smoke: `scripts/ci/smoke_backend.py`. |
| Backup | Only the local synthetic `scripts/ci/restore_drill.sh`; no managed PITR evidence. |
| Missing | provider, remote state, secret manager, DNS/TLS, telemetry backend, alert owners (D-12), approved RTO/RPO. |

## Country deployment guide (target procedure; most steps are blocked today)

1. Counsel confirms residency for the country (D-08); add an ADR/decision record.
2. Procure a provider with in-country region; fill the compatibility matrix below with evidence.
3. Add `providers/<id>` adapter with real, verified resources, and add the id to the allow-list in `country-cell/variables.tf` in the same reviewed PR.
4. Add `environments/<country>/<env>` (copy `kz/dev`), `data_region_country = country`. Separate database and secrets per country; no replication of personal data between countries.
5. Configure remote state with locking and short-lived (OIDC) credentials, then add plan → approval → apply workflow. Not implemented yet.

## Provider compatibility matrix

| Provider | Terraform provider checked | KZ/target region verified | Managed PostgreSQL + PITR | Status |
|---|---|---|---|---|
| any cloud | no | no | no | **NOT_VERIFIED** — no support claimed |
| local-compose | n/a | n/a | n/a | dev only (`compose.yaml`); never prod |

Neon/Railway/Render may serve non-production experiments only if their data location is acceptable; they are not architecture dependencies.

## Runbooks (draft, unapproved, no owners/SLOs)

- **Deploy:** build image → deploy to staging → Flyway runs on start → check `/actuator/health/readiness` → `scripts/ci/smoke_backend.py` equivalent against staging → production only after manual approval. Schema changes use expand → migrate → contract.
- **Rollback:** redeploy previous image digest (Helm: `helm rollback`). Flyway migrations are forward-only; an irreversible migration needs a forward fix or restore.
- **Backup/restore:** target is managed PITR plus encrypted snapshot in the same country. Today only the local drill exists ([restore-drill.md](../engineering-foundation/restore-drill.md)); not production evidence.
- **Disaster recovery:** RTO/RPO not approved. Cross-border backup copies are forbidden unless counsel approves.
- **Never** run `terraform destroy` or change the production database from CI.

## Cost and security constraints

Prefer a managed container service over Kubernetes for the pilot (ADR-011); Kubernetes adds platform cost and expertise. Secrets only in a secret manager; the Helm chart accepts an existing Secret name and never secret values. TLS validation is never disabled. Paid-resource creation, deletion and database changes in production require explicit approval.

## Verification actually run

`terraform fmt`, `validate`, `terraform test` (7 cases) and `plan` on `kz/prod`, `helm lint` and `helm template` (including fail-closed negatives) ran locally with Terraform 1.12.2 / Helm 3.17.0 and run in `infrastructure.yml`. The chart was **not** deployed to a cluster; no cloud API was called.
