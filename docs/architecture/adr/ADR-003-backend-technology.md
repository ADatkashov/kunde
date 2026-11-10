# ADR-003: Backend Technology

- **Status:** Proposed for review
- **Context/problem:** Need a maintainable transactional API for catalog, identity, orders, booking and finance.
- **Options:** Java/Spring Boot; Kotlin/Spring; Go; Node/TypeScript.
- **Evaluation:** Java/Spring has mature security/transaction/validation ecosystem and broad hiring; more framework/runtime surface. Kotlin retains JVM tooling with concise syntax but may not match skills. Go offers lean services but less integrated domain stack. Node can align with web team but transaction-core capability depends on team practice.
- **Decision:** Recommend Java 21 LTS with Spring Boot and strict module boundaries.
- **Consequences:** Standard JVM operations and native transaction ecosystem; protect startup/memory and dependency footprint.
- **Risks:** Team capability not assessed; framework modules could become tightly coupled.
- **Revisit when:** Team staffing, profiling, or platform needs show a materially better supported runtime.
