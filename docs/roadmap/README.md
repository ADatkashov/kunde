# KUNDE Product & Engineering Delivery Roadmap 1.0

This roadmap turns the product, functional, architecture, design and business specifications into an ordered, traceable delivery plan. It is a planning artifact; it does not implement or approve any open product, legal, vendor, or commercial decision.

## Source of truth

- Product and requirements: [PRD 1.0](../product/PRD-1.0.md), [PRD 1.1 index](../product/README.md#prd-11-index), particularly requirements traceability and open decisions.
- Technical boundaries: [Architecture](../architecture/README.md), technology stack, domain boundaries, security, data and deployment documents, and the architecture ADRs/diagrams.
- UX contracts: [Design](../design/README.md), design tokens, app specifications and accessibility/localization.
- Operating model: [Business](../business/README.md), especially Almaty launch, fulfillment, finance, legal and readiness.

The structured backlog in `backlog/` is canonical for stable IDs, status-independent scope and dependency links. Narrative documents explain sequencing and release gates. `24-master-delivery-plan.md` is the human-readable index.

## Documents

Read in order: [01 strategy](01-delivery-strategy.md), [02 scope](02-product-scope-and-prioritization.md), [03 MVP](03-mvp-definition.md), [04 releases](04-product-roadmap.md), [05 epics](05-engineering-epics.md), [06 backlog](06-development-backlog.md), [07 dependencies](07-dependency-graph.md), then discipline roadmaps 08–17, ownership/capacity 18–19, release and operations 20–21, risks 22, DoD 23, master plan 24 and [25 EP-002 Identity & Access](25-identity-ep002-design.md).

## Baseline recommendation

Use a controlled Almaty pilot for one operationally proven category. Food ordering in Almaty is the approved first category and market (D-01 partially approved 2026-11-13); the cohort, zone and launch gates remain open. Prefer merchant pickup or contractually defined partner fulfillment; no KUNDE-owned fleet is assumed. A real transactional MVP requires a selected category/cohort, approved payment and funds flow, lawful terms/privacy, staffed support, partner readiness, and a tested cancellation/refund/reconciliation path.

The implementation stack follows the architecture recommendation: Flutter consumer client; Java/Spring Boot modular backend; PostgreSQL/PostGIS; versioned REST/OpenAPI; provider adapters. Vendor and hosting selection remain subject to availability, cost, security and residency review.

## Backlog snapshot

The current baseline contains 27 epics, 35 features, 56 engineering tasks, 8 release stages and 15 tracked delivery risks. Priorities: P0 blocker/critical; P1 MVP-required; P2 post-MVP; P3 future. Release stages are order-of-work labels, not calendar promises. No velocity or team capacity is confirmed.

## Traceability and maintenance

Requirement IDs in features link back to PRD 1.1 `24-requirements-traceability.md`; feature IDs link stories and epics; task IDs link implementation/test work; releases contain the gate each item must pass. Tests are planned as acceptance requirements, not claimed as executed. Update IDs in place; do not recycle them. A requirement without a mapped feature, test evidence and release gate is not complete.

## Current readiness

Planning is ready to transition into decision closure and foundation preparation. Production implementation of real transactions is **not ready** until D-01 through D-08 and D-11/D-14 have accountable owners and approvals. See [blockers](22-delivery-risks-and-blockers.md) and [operational readiness](21-operational-readiness.md).


