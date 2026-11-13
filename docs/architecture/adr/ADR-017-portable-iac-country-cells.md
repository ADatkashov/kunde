# ADR-017: Portable IaC and country cells

- **Status:** Proposed for review (not accepted; no owner approval recorded)
- **Context/problem:** ADR-011 recommends OCI containers, managed services and IaC; ADR-012 recommends one authoritative KZ cell and per-country cells with no cross-border personal-data replication. Neither fixes the repository layout or how a new country is added.
- **Decision proposed:** Keep one backend image. Describe each deployment as a *cell* (`country` + `environment`) in `infrastructure/environments/<country>/<env>`. A provider-neutral Terraform module (`modules/country-cell`) validates and normalises the cell (residency, no cross-border replication, secret names only) and creates no cloud resources. Provider adapters (`infrastructure/providers/<id>`) are added only after procurement (TASK-051) and verified Terraform provider/API evidence. Runtime defaults to a managed container service; Helm (`helm/kunde-backend`) is used only where Kubernetes is chosen.
- **Consequences:** No provider, region, remote state, or Kubernetes requirement is decided. Production apply stays manual-approval-gated and is not implemented yet.
- **Risks:** Neutral contract may under-specify real provider needs; Kazakhstan provider options may be limited (ADR-011).
- **Revisit when:** TASK-051 selects a provider, or counsel changes the residency position.
