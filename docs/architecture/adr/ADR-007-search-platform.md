# ADR-007: Search Platform

- **Status:** Proposed for review
- **Context/problem:** Multilingual marketplace search, facets, location and availability must remain fresh enough for discovery.
- **Options:** PostgreSQL FTS/trigram; OpenSearch; Elasticsearch.
- **Evaluation:** PostgreSQL minimizes MVP operations and is sufficient for initial catalog scale; dedicated search improves relevance/facets/scale but is eventually consistent and adds region/vendor cost. OpenSearch/Elastic capabilities and licensing need current review.
- **Decision:** Start with PostgreSQL search; maintain rebuildable denormalized projection contract for later extraction.
- **Consequences:** Search is not transaction authority; canonical revalidation is mandatory.
- **Risks:** Language relevance may be limited; search load could affect OLTP if not bounded.
- **Revisit when:** Search SLO, relevance evaluation, index size or DB load exceeds agreed threshold.
