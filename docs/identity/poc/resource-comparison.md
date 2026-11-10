# Resource comparison

One non-controlled idle snapshot was captured after both stacks were healthy using `docker stats --no-stream` (Windows Docker Desktop VM limit reported as 7.713 GiB). This is a point-in-time development observation, not a capacity benchmark. Container usage depends on JVM heap sizing, database state, startup phase and Docker Desktop's VM allocation.

| Provider | Local topology | Measurement |
|---|---|---|
| Keycloak | Keycloak + PostgreSQL | Keycloak 783.8 MiB / 0.31% CPU; PostgreSQL 57.69 MiB / 0.00% CPU. |
| ZITADEL | API/login + PostgreSQL + Traefik | API 80.61 MiB / 2.02%; login 82.23 MiB / 1.23%; PostgreSQL 64.98 MiB / 0.23%; Traefik 14.98 MiB / 0.15%. |

The snapshot suggests Keycloak's JVM has a higher idle footprint in this specific configuration; the provider topologies are not equivalent in enabled features and this single sample says nothing about peak capacity. For a repeatable comparison, record image digest, OS, provider configuration, number of synthetic users/clients, idle and authenticated load, sampling duration and container-level CPU/memory. Measure identical request rates and include database memory. Do not use this local laptop POC as production capacity evidence.
