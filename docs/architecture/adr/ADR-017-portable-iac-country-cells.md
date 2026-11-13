# ADR-017: Portable IaC and country cells

- **Status:** Proposed for review (not accepted; no owner approval recorded)
- **Context/problem:** ADR-011 recommends OCI containers, managed services and IaC; ADR-012 recommends one authoritative KZ cell and per-country cells with no cross-border personal-data replication. Neither fixes the repository layout or how a new country is added.
- **Decision proposed:** Keep one backend image. Describe each deployment as a *cell* (`country` + `environment`) in `infrastructure/terraform/environments/<env>` (later `<country>-<env>`). A provider-neutral Terraform module (`infrastructure/terraform/modules/country-cell`) validates and normalises the cell (residency, no cross-border replication, secret names only) and creates no cloud resources. Provider adapters are Terraform modules added only with verified provider/API evidence; Render Free + Neon Free is accepted by the owner (2026-11-13 request) for **DEV with synthetic data only**, never prod; production provider still needs TASK-051. Runtime defaults to a managed container service; Helm (`helm/kunde-backend`) is used only where Kubernetes is chosen.
- **Consequences:** No provider, region, remote state, or Kubernetes requirement is decided. Production apply stays manual-approval-gated and is not implemented yet.
- **Risks:** Neutral contract may under-specify real provider needs; Kazakhstan provider options may be limited (ADR-011).
- **Revisit when:** TASK-051 selects a provider, or counsel changes the residency position.
