# KUNDE DEV on Render Free + Neon Free (Terraform)

**Status:** code, offline tests and a dummy-credential `plan` exist. **Nothing has been applied**: no Render/Neon account credentials, remote state bucket or GitHub Environment were available to the agent, and no apply was authorised. DEV only, **synthetic data only** (neither Render nor Neon free has a Kazakhstan region; D-08 residency is untouched; production is not covered).

## What Terraform owns

`infrastructure/terraform/environments/dev` → modules `country-cell` (cell contract), `neon` (`neon_project`, provider `kislerdm/neon` 0.18.0, community), `render` (`render_web_service`, provider `render-oss/render` 1.9.1, official partner). Resources: 1 Neon project (default branch/role/database, PostgreSQL 16, `aws-eu-central-1`) and 1 Render Docker web service (free plan, Frankfurt) built from `backend/Dockerfile`, unchanged. Flyway runs at application start (V1–V8, verified locally).

Rules enforced in code: only `plan = "free"`; DB URL must contain `sslmode`; JDBC URL uses `verify-full` (certificate and host name checked with the JVM trust store); no secret value in Git; Render env values are sensitive; `scripts/ci/check_terraform_policy.py` rejects tracked state/tfvars/plans, weakened TLS, embedded credentials, `-auto-approve` outside the apply workflow and destroy in automation.

## Free-tier facts and limits (sources checked 2026-11-13)

- Render free web service: 512 MB RAM, 0.1 CPU, spins down after ~15 min idle (cold start about a minute), 750 instance-hours/month (Render docs and articles, 2026); no disks, scaling or pre-deploy command. The provider documents plans `starter`+ only, but `plan = "free"` passes provider validation and plans offline; whether the API accepts it on create is **unverified until the first apply**.
- Neon free: per-project 100 CU-hours/month, storage cap (Neon FAQ says 1 GB, other sources 0.5 GB — check the live plans page), compute suspends after 5 min idle ([Neon FAQ](https://neon.com/faqs/free-plan-limits-and-quotas)). Free PITR history window is short; do not treat it as production backup.
- Neon provider is community-maintained, `0.x`: pinned exactly.

## Memory (512 MB)

`backend/Dockerfile` uses `MaxRAMPercentage=75` (≈384 MB heap in a 512 MB container: too large with metaspace/threads). Terraform sets `JAVA_TOOL_OPTIONS=-Xmx256m -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -Xss512k -XX:+UseSerialGC -XX:TieredStopAtLevel=1` (explicit `-Xmx` overrides the percentage) and `DB_POOL_SIZE=5`.
Measured locally (packaged JAR, those flags, local PostgreSQL 16, synthetic data): ready in 6 s, 8 Flyway migrations applied, 200 requests, peak RSS **≈230 MB**. Not measured: Render's cgroup, Neon TLS handshake, Render image build (the Dockerfile's Maven `ADD --checksum` step and Maven build memory on Render's builder are **unverified**; a build OOM would need a prebuilt image instead of Terraform `docker` source).

## Bootstrap (one-time, by the owner)

1. Create a **private, versioned, encrypted** S3-compatible bucket for state and a key limited to that bucket. State holds the Neon password and Render env values — treat it as a secret. Locking uses Terraform's native `use_lockfile` (needs conditional writes). Cloudflare R2 support is **unverified**: before relying on it, run two concurrent `terraform plan` against a scratch key and confirm the second one fails with a lock error; if it does not, use AWS S3 or another backend.
2. Create Neon and Render API keys; note the Render owner id (`usr-…`/`tea-…`). Use accounts on free plans with no payment method where possible.
3. GitHub → Settings → Environments: `dev-plan` (secrets `RENDER_API_KEY`, `NEON_API_KEY`, `TF_STATE_ACCESS_KEY_ID`, `TF_STATE_SECRET_ACCESS_KEY`; variables `RENDER_OWNER_ID`, `TF_STATE_BUCKET`, `TF_STATE_ENDPOINT`, optional `TF_STATE_REGION`) and `dev` (same secrets/variables **plus required reviewers** — this is the manual approval gate).
4. Actions → "Terraform DEV (Render + Neon)" → Run workflow: first with `apply` off to read the plan. Then run with `apply = true`, `confirm = apply-dev`; approve the `dev` environment. The apply job re-plans, refuses to continue if the plan differs from the reviewed one, applies that saved plan, and smoke-tests readiness, fail-closed auth (503) and the OpenAPI document.

Local alternative (same code): copy `backend.hcl.example` to `backend.hcl`, export `RENDER_API_KEY`, `RENDER_OWNER_ID`, `NEON_API_KEY` and state credentials, then `terraform init -backend-config=backend.hcl && terraform plan`.

## Destroy DEV

Never from automation. Locally with the same credentials: `terraform destroy` in `environments/dev`, review the plan, type `yes`. This deletes the Neon project and all its data and the Render service. Run only after confirming the data is synthetic.

## Rollback and recovery

- **App:** Render dashboard → Deploys → redeploy a previous successful deploy, or revert the commit and redeploy (auto-deploy is off by default; `auto_deploy` variable turns it on). Flyway is forward-only: a bad migration needs a forward-fix migration or a database restore.
- **Infra change:** revert the Git commit and re-run the plan/apply workflow.
- **Database:** Neon branch restore inside the free history window, or recreate DEV (destroy + apply) and let Flyway rebuild the schema from V1; DEV data is synthetic and disposable.
- **State:** bucket versioning is the recovery path for a corrupted/deleted state file; a lost state needs `terraform import` of the Neon project and the Render service.
- **Stuck lock:** confirm no run is active, then `terraform force-unlock <id>`.

## Portability

Another cloud = a new adapter module with the same inputs/outputs as `neon`/`render` (db url/user/password; service url), a new allow-listed `provider_id` in `country-cell`, and an environment root per `<country>-<env>`. The contract refuses prod on `render-neon` and personal data outside the country.

## Evidence actually produced

Local: `terraform fmt`, `validate`; `terraform test` — country-cell 11, neon 1, render 4 (mocked providers); `plan` of `environments/dev` against the real provider schemas with dummy credentials: 3 resources to add, free plan accepted by provider validation; policy script and 47 `scripts/ci` tests; backend JAR run under the 512 MB-sized JVM flags as above. Not run: any API call to Render or Neon, apply, remote-state locking, TLS to Neon, Render build.
