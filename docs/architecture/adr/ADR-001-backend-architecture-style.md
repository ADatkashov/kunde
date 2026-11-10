# ADR-001: Backend Architecture Style

- **Status:** Proposed for review
- **Context/problem:** KUNDE has many related domains, needs transactional correctness and future scaling, but has no established service teams or workload numbers.
- **Options:** Modular monolith; microservices from day one; hybrid with modular core plus independently operated infrastructure adapters.
- **Evaluation:** Monolith provides simple ACID and lower on-call/infra cost, but needs module discipline. Microservices allow independent deployment/scale but add network failure, distributed data and staffing costs. Hybrid lets async/read-heavy edges scale independently without splitting core transactions.
- **Decision:** Modular monolith for core domains, hybrid adapters/workers; define extraction-ready interfaces and data ownership.
- **Consequences:** One primary deployable and DB boundary; shared outage domain. Architecture checks and schema ownership required. Avoid distributed transactions.
- **Risks:** Boundary erosion, noisy neighbor modules, migration complexity.
- **Revisit when:** Independent team ownership, specific SLO isolation, measured scaling pressure or jurisdiction boundary cannot be met within one deployable.
