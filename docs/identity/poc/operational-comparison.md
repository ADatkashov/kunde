# Operational comparison — recovery 3.0

Local Docker Desktop on Windows; observations are local POC only, not production sizing or a load test.

| Measure | Keycloak 26.8.2 | ZITADEL 4.19.5 | Evidence/limit |
|---|---|---|---|
| Containers | Keycloak + PostgreSQL (2) | API + Login UI + PostgreSQL + Traefik (4) | Existing Compose definitions; provider stacks isolated |
| Database | PostgreSQL required in this POC | PostgreSQL required in this POC | Not a statement about every supported deployment topology |
| Startup | Previously ~35s until server ready; initial full-compose timing not captured | Recovery run full health-gated Compose startup 96.1s | One run each, no controlled benchmark; ZITADEL startup includes database initialization |
| Idle memory/CPU | Previous settled snapshot: server 918.2 MiB and DB 53.81 MiB; CPU 0.39% / 1.83% instant sample | No comparable settled idle snapshot in recovery | Docker VM max 7.713 GiB in prior observation; CPU samples instantaneous |
| Configuration | Realm import, public client, explicit optional offline scope and subject mapper repair | Bootstrap secrets; manual org/project/native application/roles/user still needed | Setup tasks are at different completion points; no complexity ranking |
| Health/recovery | Healthy stack; no restore/failover drill | Four components healthy after 96.1s; discovery endpoints returned | Health is not recovery/availability evidence |
| Networking | Loopback-only 8180, Android via ADB reverse | Loopback-only 8280, Android via ADB reverse if tested | No LAN/internet exposure |
| Logs/monitoring | Container logs and health probes available; no monitoring integration validated | Container logs/health probes; no monitoring integration validated | No production observability test |
| Backup/upgrade | Not tested | Not tested | Define database, realm/project config, secrets and recovery procedures |

Keycloak has fewer components in the current POC. That does not prove lower total operational cost. Do not compare the prior Keycloak idle snapshot with a ZITADEL startup/active snapshot. Neither has load, HA, backup/restore or upgrade evidence. Kazakhstan placement, contract/support, staffing and operating costs are unassessed.
