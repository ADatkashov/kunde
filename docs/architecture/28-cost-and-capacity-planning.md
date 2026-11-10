# 28 — Cost and Capacity Planning

No exact prices are estimated because providers, workload, region and contracts are unknown. Use relative cost drivers and validate vendor quotes before procurement.

| Cost category | Early MVP | Initial growth | Multi-city | International |
|---|---|---|---|---|
| Backend compute | Low: one app + worker footprint | Medium: replicas/worker scaling | High: city/region capacity | High: separate regional cells |
| Database/backup | Medium fixed floor; largest critical baseline | Medium-high from storage/IO/HA | High from replicas/partitioning | High: regional HA and residency |
| Search | Low using PostgreSQL | Medium if OpenSearch introduced | Medium-high multi-language indexes | High, region-specific clusters |
| Queue/messaging | Low outbox; OTP/SMS variable | Medium with fanout | High notification volume | High local channels and delivery |
| Maps/routing | Usage-based, can dominate mobility | Higher with trip density | High, provider coverage by city | High and vendor-specific per market |
| AI inference | Limit with quotas and simple retrieval | Variable by tasks/tokens | Higher personalization/task volume | High plus regional model/data constraints |
| Object storage/CDN | Low initially, image/evidence growth | Medium | Medium-high | High cache/egress and regional copies |
| Observability | Low/moderate, retention matters | Medium | High telemetry volume | High multi-region retention/access |
| Security/compliance/ops | Fixed staffing/audit costs | Higher on-call/support | Regional ops | Highest legal/support/vendor work |

## Capacity model inputs

DAU/MAU, peak concurrency, request mix, p95 target, catalog index size, transactions/day, payment/webhook rate, dispatch updates/sec, AI turns/task and tokens, media GB/month, data retention, logs GB/day, backup retention, network egress and support hours. Model low/base/high scenarios and include provider fees, taxes, FX, minimum commitments and data-egress costs.

## Cost controls

Per-provider quotas and alerts; AI model routing/task budgets and hard user/tenant spend cap; image sizing/CDN; log sampling/redaction/retention; queue batching; database query/index review; scheduled nonproduction shutdown; cost allocation tags by environment/domain. Do not trade transaction integrity or consent for cost reduction. Revisit deferred Redis/OpenSearch/Kafka/Kubernetes only with quantified cost/performance case.
