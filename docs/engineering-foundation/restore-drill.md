# Local restore drill (TASK-056, in progress)

`scripts/ci/restore_drill.sh` is a **local, synthetic** drill; it is not production backup evidence.

What it does: starts a throwaway PostgreSQL cluster on a unix socket, applies the Flyway SQL files
in `backend/src/main/resources/db/migration` in order (with `psql`, not Flyway), loads a few synthetic
catalog rows, runs `pg_dump -Fc`, restores into a fresh database with `pg_restore --exit-on-error`,
and compares (1) catalog structure (columns, constraint names/types, indexes) and (2) a per-table row
count and md5 fingerprint. A tamper step must make the fingerprint differ.

Run (non-root; `initdb` refuses root): `runuser -u postgres -- bash scripts/ci/restore_drill.sh`
(or any non-root user; `PG_BIN` overrides the PostgreSQL bin directory). Local result 2026-11-13,
PostgreSQL 16.15: both checks PASS (12 tables). It is not wired into CI.

A raw `pg_dump -s` diff is not used: it embeds a random `\restrict` token and the restored database
deparses CHECK expressions differently (same meaning, different text).

Not covered, still open: managed PITR/snapshots, encryption/KMS, Kazakhstan region and backup
location (D-08, D-12, TASK-051), retention vs. deletion policy, RTO/RPO, restore cadence, runbook and
operations owner. See `docs/architecture/19-infrastructure-and-deployment.md` and
`docs/architecture/23-reliability-and-disaster-recovery.md`.
