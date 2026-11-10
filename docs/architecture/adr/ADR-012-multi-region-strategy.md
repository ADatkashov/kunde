# ADR-012: Multi-Region and Data Residency

- **Status:** Proposed for review
- **Context/problem:** KUNDE intends future international expansion, but Kazakhstan data-residency and cross-border rules constrain initial data placement.
- **Options:** Global active-active; single global database; per-country data cells; regionally partitioned service with cross-border control plane.
- **Evaluation:** Active-active writes complicate money, booking and residency. Single global store risks compliance and latency. Per-country cells isolate data and allow local processing but increase operational cost. Control plane must minimize PII.
- **Decision:** One authoritative KZ cell for initial market; design country/region ID and per-country cell boundary; no cross-border replication of personal data by default.
- **Consequences:** Global identity/analytics need explicit pseudonymization and legal basis; city expansion within Kazakhstan may remain same cell if validated.
- **Risks:** Duplicated operations, account portability and vendor region limitations.
- **Revisit when:** New country chosen, counsel approves transfer/processing, and demand justifies regional cell.
