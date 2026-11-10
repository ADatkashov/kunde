# 24 — Master Delivery Plan

## Sequence

1. **Decision closure and discovery:** resolve category/cohort (D-01), fulfillment (D-02), payment/funds/tax (D-03/D-04), response and cancellation/refund rules (D-05/D-06), identity and data/legal (D-07/D-08), external providers (D-11), SLOs (D-12), admin finance controls (D-14), language (D-15). Assign named owners.
2. **Foundation:** contract/domain review, project and CI baseline, localization/design primitives, identity/security, schema/migration ownership, telemetry, backup and staged environments.
3. **Pilot product slice:** catalog/serviceability, partner onboarding/work queue, consumer discovery/detail/quote, order lifecycle, approved payment/fulfillment adapters, support/admin, notifications and audit.
4. **Validation:** automated quality gates, sandbox/provider contracts, E2E failure and recovery rehearsal, reconciliation, restore/incident exercise, user/partner closed beta.
5. **Limited production:** launch one category in a proven Almaty zone/hours only after technical and business Go criteria; measure, pause on thresholds, expand one increment at a time.
6. **Expansion:** category, service, AI, city and country releases each receive separate evidence, legal and operational gates.

## Traceability chain

`PRD requirement → PRD 1.1 story/AC → FEAT-* (epic + release) → TASK-* (implementation + tests + DoD) → release gate/evidence`. Requirement IDs are preserved in feature records. Test plans are explicit in tasks and testing roadmap; future implementation must add test/run evidence, not infer it from this document.

## Critical path and decision register

Critical path is shown in [07-dependency-graph.md](07-dependency-graph.md). Launch blockers are D-01–D-08 as applicable, plus D-11/D-12/D-14 and operating readiness. Full source register is [PRD 1.1 open decisions](../product/PRD-1.1/23-assumptions-and-open-decisions.md); tracked delivery risks are in `backlog/risks.yaml`.

## Release map

Foundation → MVP closed pilot → limited production → marketplace expansion → everyday services → lifestyle → AI → Kazakhstan cities → international. Details and Go/No-Go are in `backlog/releases.yaml`; no dates are committed.

## First work

Recommended first engineering epic is **EP-001 Project Foundation**, preceded by decision ownership and architecture/API baseline. Start with TASK-001 (assign/track decision owners), TASK-002 (review architecture and repository baseline), TASK-003 (map approved domain/API contracts), TASK-004 (define CI/review gates) and TASK-005 (initial privacy/threat review). These are planning/foundation-enabling tasks. Do not start real payment or public transactional rollout before the corresponding blocker decisions are signed.

## Readiness conclusion

KUNDE is ready to move from specification into controlled foundation work. It is not ready for implementation of production money flows or a public Almaty launch: category, fulfillment, financial/legal, privacy, vendor, operational and capacity decisions are unresolved. This distinction is the principal Go/No-Go result of this roadmap.

## Foundation implementation status

Development Foundation 1.0 is in progress. Flutter analysis, four tests and Android debug build passed; backend build/database tests remain unverified after Docker Hub aborted the Maven base-image download. Task-level states are recorded in [`backlog/tasks.yaml`](backlog/tasks.yaml), and implementation evidence/limitations are recorded in [`docs/engineering-foundation/implementation-status.md`](../engineering-foundation/implementation-status.md). The initial code does not close any PRD launch blocker.

