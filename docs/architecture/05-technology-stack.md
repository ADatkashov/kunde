# 05 — Technology Stack Evaluation

Selection uses project needs, team operations and jurisdiction as criteria, not popularity. Existing seed source files happen to use Flutter/Spring Boot; the recommendations below are evaluated on their merits and do not claim those files are production-ready.

## Application and backend

| Area | Recommended | Alternatives and tradeoffs |
|---|---|---|
| Consumer mobile | Flutter/Dart: one UI codebase for iOS/Android, consistent localization/accessibility, fast shared feature delivery. Requires plugin governance and platform-specific integration skills. | React Native: JS/TS ecosystem and hiring; native modules/bridge compatibility need care. Native Swift/Kotlin: best platform integration/perf, but duplicate delivery/team cost. Choose native only for demonstrated platform requirements. |
| Backend | Java 21 LTS + Spring Boot modular application: mature transaction/security/validation/observability ecosystem and clear hiring pool. Runtime footprint and framework surface are higher than lightweight stacks; guard module boundaries. | Kotlin on Spring shares JVM ecosystem and concise syntax but may not improve team throughput without Kotlin skills. Go is lean for network services but adds ecosystem/domain consistency cost. Node/TS may suit BFF; less compelling as first financial marketplace core absent team preference. |
| API | REST/JSON + OpenAPI v3 for client/partner commands and queries; SSE only for simple live updates where polling is insufficient. | GraphQL adds schema/resolver complexity and auth review; WebSocket adds connection lifecycle and scaling burden. Neither needed for MVP assumption. |

## Data and messaging

| Area | Recommended | Alternatives and tradeoffs |
|---|---|---|
| Transaction DB | PostgreSQL, managed if an acceptable in-country service exists. Strong relational constraints, transactions, JSONB for bounded extensions, mature tooling. | MySQL viable but weaker fit for unified relational/geo needs; NoSQL is not required for core transaction correctness. |
| Geospatial | PostGIS in same PostgreSQL boundary. Avoids sync drift and supports service areas/indexed proximity. Validate query plans at scale. | External maps API for geocoding/routing is complementary, not source of truth for address/serviceability. |
| Cache | No cache initially except measured hot, safe data; Redis-compatible managed cache when needed. Never cache authorization as final authority or payment state. | Local cache simpler but node-local; Redis introduces another failure/deployment dependency. |
| Search | PostgreSQL full text/trigram for initial catalog/search. OpenSearch when relevance tuning, facets, multilingual scale or indexing throughput require it. | Elasticsearch has similar capabilities and potential licensing/vendor considerations; managed search availability in Kazakhstan must be checked. |
| Async | PostgreSQL transactional outbox; a managed queue for durable delivery when operational need exists. RabbitMQ suits work queues/routing; Kafka suits high-volume replayable event streams but has higher operations cost. | Do not select Kafka merely for domain events; outbox + polling may be sufficient early. |
| Analytics | Export minimized, versioned events to a separate analytical store when product reporting exceeds transactional DB; select after data-region review. | Initially aggregate from operational events/DB views with load controls. Avoid raw PII replication. |
| Object storage | S3-compatible regional object storage for receipts/evidence/media, encrypted and private by default; CDN only for public assets. | Vendor API compatibility is not a residency guarantee; verify data location, backup and deletion behavior. |

## Infrastructure, AI and final recommendation

| Area | Recommendation | Alternative / tradeoff |
|---|---|---|
| Runtime | OCI containers; managed container runtime or VM orchestration initially. Kubernetes only if team can operate it and multi-service scheduling/scale warrants it. | K8s is portable but incurs control-plane, security and on-call costs. |
| IaC/secrets | Terraform/OpenTofu-class IaC after cloud selection; managed secrets/KMS with rotation and audit. | Provider-native IaC can reduce friction but increase lock-in. |
| CDN | CDN for static/public catalog assets after residency and cache policy review; private user content remains authenticated. | No CDN needed for first low-volume pilot. |
| AI | Provider-neutral gateway, structured tools, policy/confirmation checks, model routing by task class; store minimal context. | Vector DB not required initially; use relational search/retrieval and add vector index only for a measured semantic retrieval problem. |

**Recommended initial stack:** Flutter; Java 21/Spring Boot; PostgreSQL + PostGIS; REST/OpenAPI; outbox plus managed queue when needed; provider adapters; containerized deployment in a verified Kazakhstan region; managed secrets and object storage; OpenTelemetry-compatible telemetry. Defer Redis, OpenSearch, Kafka, Kubernetes, vector DB, global multi-region and a dedicated data warehouse until explicit triggers. For each managed service, procurement must verify in-country storage and processing capability before personal data is placed there.
