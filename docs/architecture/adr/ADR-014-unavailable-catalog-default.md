# ADR-014: No Default Orderable Catalog

- **Status:** Accepted for the reversible foundation implementation; does not resolve PRD decision D-01.
- **Context:** The seed exposed eight hard-coded categories although the launch category and operating cohort are undecided. Static labels can be mistaken for real supply.
- **Decision:** Return empty category/search results and report `marketplaceEnabled=false`. Do not seed categories as orderable or show a placeholder AI/search flow. Implement catalog persistence and activation only after category, partner verification, serviceability and operational gates are approved.
- **Consequences:** Initial mobile experience is an honest foundation/availability shell. Catalog delivery remains future work.
- **Alternatives:** Show all eight (rejected: suggests unavailable services); show food (rejected: D-01 open); use local demo data (rejected: misleading interaction).
- **Update 2026-11-13:** D-01 is partially approved (Food Ordering, Almaty; see PRD 1.1 §23). This ADR's status and decision are unchanged: the catalog stays empty and non-orderable until partner verification, serviceability and payment/fulfillment gates are met.
- **Revisit when:** Product/operations approve the first cohort and real catalog/API contracts are ready.
