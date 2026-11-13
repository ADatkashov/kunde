# KUNDE DEV on Render Free + Neon Free (Terraform)

**Status:** code, offline tests and a dummy-credential `plan` exist. **Nothing has been applied**: the agent has no provider API keys, HCP Terraform workspace or access to GitHub Environments/Secrets, and no apply was authorised. DEV only, **synthetic data only** (neither Render nor Neon free has a Kazakhstan region; D-08 residency is untouched; production is not covered).

## What Terraform owns

`infrastructure/terraform/environments/dev` → modules `country-cell` (cell contract), `neon` (`neon_project`, provider `kislerdm/neon` 0.18.0, community), `render` (`render_web_service`, provider `render-oss/render` 1.9.1, official partner). Resources: 1 Neon project (default branch/role/database, PostgreSQL 16, `aws-eu-central-1`) and 1 Render Docker web service (free plan, Frankfurt) built from `backend/Dockerfile`, unchanged. Flyway runs at application start (V1–V8, verified locally).

Resources are named `kunde-dev` (Neon) and `kunde-backend` (Render). Rules enforced in code: only `plan = "free"`; DB URL must contain `sslmode`; JDBC URL uses `verify-full` (certificate and host name checked with the JVM trust store); no secret value in Git; Render env values are sensitive; `scripts/ci/check_terraform_policy.py` rejects tracked state/tfvars/plans, weakened TLS, embedded credentials, `-auto-approve` outside the apply workflow and destroy in automation.

## Free-tier facts and limits (sources checked 2026-11-13)

- Render free web service: 512 MB RAM, 0.1 CPU, spins down after ~15 min idle (cold start about a minute), 750 instance-hours/month (Render docs and articles, 2026); no disks, scaling or pre-deploy command. The provider documents plans `starter`+ only, but `plan = "free"` passes provider validation and plans offline; whether the API accepts it on create is **unverified until the first apply**.
- Neon free: per-project 100 CU-hours/month, storage cap (Neon FAQ says 1 GB, other sources 0.5 GB — check the live plans page), compute suspends after 5 min idle ([Neon FAQ](https://neon.com/faqs/free-plan-limits-and-quotas)). Free PITR history window is short; do not treat it as production backup.
- Neon provider is community-maintained, `0.x`: pinned exactly.

## Memory (512 MB)

`backend/Dockerfile` uses `MaxRAMPercentage=75` (≈384 MB heap in a 512 MB container: too large with metaspace/threads). Terraform sets `JAVA_TOOL_OPTIONS=-Xmx256m -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -Xss512k -XX:+UseSerialGC -XX:TieredStopAtLevel=1` (explicit `-Xmx` overrides the percentage) and `DB_POOL_SIZE=5`. Hikari is set to `minimum-idle=0`, `idle-timeout=30s`, `connection-timeout=10s` so idle connections close and the Neon compute can autosuspend (free: 100 CU-hours/month; verified locally: 2 connections → 0 after 45 s idle); Render health check uses `/actuator/health/liveness` so it does not hold the database awake. The pinned base images are linux/amd64 only (Render is amd64; Apple-silicon builds run under emulation). Graceful shutdown: Spring 20 s; Render `max_shutdown_delay_seconds` is not supported on the free plan (the API rejected it at the first apply), so it is not set.
Measured locally (packaged JAR, those flags, local PostgreSQL 16, synthetic data): ready in 6 s, 8 Flyway migrations applied, 200 requests, peak RSS **≈230 MB**. Not measured: Render's cgroup, Neon TLS handshake, Render image build (the Dockerfile's Maven `ADD --checksum` step and Maven build memory on Render's builder are **unverified**; a build OOM would need a prebuilt image instead of Terraform `docker` source).

## Pre-flight findings (read-only inspection, 2026-11-13)

- **Render:** workspace "My Workspace" (`tea-…`, team). It already hosts 6 free Docker web services and 3 static sites of other projects (none named `kunde-*`, so no name collision). Free web services in a workspace **share 750 instance-hours/month**: an extra always-busy service can exhaust the pool and suspend the others. Idle services spin down, so this is a risk, not a certainty; watch usage after the first deploy. The repository is public, so Render needs no GitHub connection to build it.
- **Neon:** organization "Arsylan", plan Free, 6 existing projects (none named `kunde-dev`). Projects are organization-owned, so Terraform needs `org_id` (GitHub variable `NEON_ORG_ID`, passed as `TF_VAR_neon_org_id`). Existing projects use 21600 s PITR history, the Free cap; the module sets the same (the provider default of 1 day would have been rejected or paid).
- **GitHub:** the Environments/Secrets API is not reachable from the agent session, so their current state is **unverified** and nothing could be created there; steps below are for the owner.

## State backend: HCP Terraform Free

Chosen over the S3-compatible option from the first draft because the S3 native lock on non-AWS stores was unverified. HCP Terraform Free provides remote state that is encrypted, versioned (recovery) and locked during runs, with access control by team/token; sources report a 500-managed-resource cap and one concurrent run ([IBM/HashiCorp limits](https://www.ibm.com/support/pages/hcp-terraform-limits)) — confirm on the live plan page. This Terraform root manages 3 resources. The workspace must use **Local execution** so plans/applies run in GitHub Actions; state is still stored and locked in HCP. State contains the Neon password and Render env values: restrict workspace access to the owner.

## Bootstrap (one-time, by the owner; never paste keys in chat)

1. HCP Terraform: create a free organization and a workspace `kunde-dev` (CLI-driven, **Execution mode: Local**). Create a team/user API token limited to that workspace.
2. Render: Account Settings → API Keys → create a key. Neon: Account → API keys → create a key (organization "Arsylan").
3. GitHub → Settings → Environments → create `dev-plan` and `dev`; in **both** add *environment secrets* (not repository secrets): `RENDER_API_KEY`, `NEON_API_KEY`, `TF_API_TOKEN`; and *environment variables*: `RENDER_OWNER_ID` (the workspace id `tea-…`), `NEON_ORG_ID`, `TF_CLOUD_ORGANIZATION`, `TF_WORKSPACE`. In `dev` add **required reviewers** (the repository is public, so GitHub supports this). Keep `TF_APPLY_ENABLED` unset until you intend to apply.
4. Actions → "Terraform DEV (Render + Neon)" → Run workflow with `apply` off. It validates, plans, prints the plan and runs the cost gate (`check_terraform_plan.py`: free plan only, one instance, no disk, no deletes, no sensitive outputs). Nothing is created.
5. To apply: set `TF_APPLY_ENABLED=true` in `dev`, run with `apply = true`, `confirm = apply-dev`, approve the environment. The job re-plans, aborts if the plan differs from the reviewed one, applies that plan and smoke-tests the service.

Limitations: a job that references a missing Environment makes GitHub create it **without** reviewers, which is why secrets live only in environment secrets and `TF_APPLY_ENABLED` is an extra switch; `dev-plan` holds the same provider keys as `dev` (Render/Neon keys cannot be made read-only), so plan-only is enforced by the workflow, not by key scope.

Local alternative (same code): export the same variables (`TF_TOKEN_app_terraform_io`, `TF_CLOUD_ORGANIZATION`, `TF_WORKSPACE`, provider keys, `TF_VAR_neon_org_id`) and run `terraform init && terraform plan` in `environments/dev`.

## Destroy DEV

Never from automation. Locally with the same credentials: `terraform destroy` in `environments/dev`, review the plan, type `yes`. This deletes the Neon project and all its data and the Render service. Run only after confirming the data is synthetic.

## Rollback and recovery

- **App:** Render dashboard → Deploys → redeploy a previous successful deploy, or revert the commit and redeploy (auto-deploy is off by default; `auto_deploy` variable turns it on). Flyway is forward-only: a bad migration needs a forward-fix migration or a database restore.
- **Infra change:** revert the Git commit and re-run the plan/apply workflow.
- **Database:** Neon branch restore inside the free history window, or recreate DEV (destroy + apply) and let Flyway rebuild the schema from V1; DEV data is synthetic and disposable.
- **State:** HCP Terraform keeps state versions (restore a previous one from the workspace UI); a lost state needs `terraform import` of the Neon project and the Render service.
- **Stuck lock:** confirm no run is active, then `terraform force-unlock <id>`.

## Portability

Another cloud = a new adapter module with the same inputs/outputs as `neon`/`render` (db url/user/password; service url), a new allow-listed `provider_id` in `country-cell`, and an environment root per `<country>-<env>`. The contract refuses prod on `render-neon` and personal data outside the country.

## Evidence actually produced

Local: `terraform fmt`, `validate`; `terraform test` — country-cell 11, neon 1, render 4 (mocked providers); `plan` of `environments/dev` against the real provider schemas with dummy credentials: 3 resources to add, free plan accepted by provider validation; policy script and 47 `scripts/ci` tests; backend JAR run under the 512 MB-sized JVM flags as above. Not run: apply, any state in HCP Terraform, TLS to Neon, Render build.
