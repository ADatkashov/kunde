# ADR-011: Infrastructure Strategy

- **Status:** Proposed for review
- **Context/problem:** Platform must launch in Almaty with secure operations while remaining portable and internationally expandable.
- **Options:** Cloud-native managed services; self-managed Kubernetes; VM/container platform; hybrid.
- **Evaluation:** Managed database/runtime reduce operations but region/residency/support details matter. Kubernetes improves orchestration/portability at the cost of platform expertise. VM containers can be simpler initially but need HA automation.
- **Decision:** Recommend OCI containers and managed services in a verified Kazakhstan region; defer Kubernetes unless capability/scale requires it. Use IaC/secrets management.
- **Consequences:** Cloud provider is not selected; procurement scorecard and exit plan required.
- **Risks:** In-country service menu may be limited; managed backups/log/support can cross borders.
- **Revisit when:** Vendor due diligence and workload/availability requirements show a viable option.
