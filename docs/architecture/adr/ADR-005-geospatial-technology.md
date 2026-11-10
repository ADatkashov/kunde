# ADR-005: Geospatial Technology

- **Status:** Proposed for review
- **Context/problem:** User addresses, service areas, proximity, appointment location and mobility need geo-aware operations.
- **Options:** PostgreSQL/PostGIS; external geo database; provider-only geocoding/routing.
- **Evaluation:** PostGIS keeps serviceability predicates with canonical data and avoids projection drift. External provider is useful for geocoding/routes but not a KUNDE availability authority. Separate geo DB adds sync and ops cost.
- **Decision:** Recommend PostGIS for first-party geometry/service-area operations; adapter interfaces for geocoding/routing/maps.
- **Consequences:** Validate SRID/index/query plans; minimize external coordinate sharing.
- **Risks:** Provider coverage, residency, licensing and region availability unknown.
- **Revisit when:** Measured geo scale or local coverage makes PostGIS insufficient.
