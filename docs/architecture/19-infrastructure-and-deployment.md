# 19 — Infrastructure and Deployment

## Environments and region

Development uses synthetic data/local containers; test uses isolated nonproduction data; staging approximates production controls with masked fixtures; production has separate accounts/projects, network, keys and access. Initial production data plane must be in a verified Kazakhstan region due personal-data storage constraints; vendor availability and actual backup/telemetry locations are procurement gates. Do not copy production PII to developer laptops or non-KZ staging.

## Runtime topology

Container image for API and optional worker, reverse proxy/API edge, PostgreSQL, private object storage, secrets/KMS, telemetry collector and optional queue. Managed runtime/VM service is preferred for initial operational simplicity. Kubernetes only after team capability and service count justify it. Private subnets for DB/worker; public ingress limited to edge; outbound egress allowlisted where practical.

## Release/deploy

Build immutable signed artifacts; deploy to staging; smoke and migration compatibility checks; gradual production rollout (rolling deployment adequate for one app; canary if traffic controls exist). Database expand-migrate-contract before app rollout. Rollback app independently; forward-fix irreversible schema/data migrations from tested recovery plan. Feature flags disable category/integration independently.

## Backup and storage

Managed PostgreSQL PITR plus encrypted snapshot, regional/object backup under residency review, restore test cadence defined by SLO. Object upload uses signed short-lived URL, scanning and private ACL; CDN only for public media. Backup retention/deletion must align with legal retention and account deletion policy.

## Vendor decision

Cloud provider cannot be selected from this spec because Kazakhstan region/data-residency evidence, managed database/queue availability, legal terms and support commitments have not been validated. Procurement scorecard: region, services, encryption, IAM, backup, telemetry location, incident SLA, lock-in, exit/data export, cost and support.
