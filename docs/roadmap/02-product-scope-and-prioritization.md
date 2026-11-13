# 02 — Product Scope & Prioritization

The detailed feature inventory, acceptance summaries, PRD links and release targets are in [`backlog/features.yaml`](backlog/features.yaml). It contains 35 justified features with stable IDs. This document states the decision rules and major boundaries.

## Prioritization rules

- **P0 — Blocker/Critical:** decision closure, identity/authorization, money/state integrity, operational controls or release prerequisites. A P0 can be a readiness task rather than customer-facing functionality.
- **P1 — Required for MVP:** only capabilities needed for the selected category's safe discover-to-fulfillment journey and support.
- **P2 — Important after MVP:** improve conversion, retention or operational efficiency after pilot evidence.
- **P3 — Future:** multi-category, regulated/high-complexity, proactive or multi-market capabilities.

MoSCoW: P0/P1 are Must for the relevant gate; P2 is Should/Could based on evidence; P3 is Won't for the initial pilot. A conditional item becomes Must only when the selected operating model requires it.

## MVP value proposition

Let a customer in a serviceable Almaty zone find an available offering from a verified partner, understand price and fulfillment terms, place one merchant-scoped request, receive a truthful status, and get human support when it fails. Give the partner an actionable work queue and KUNDE operations a way to resolve exceptions and reconcile money. This is a narrower marketplace, not a generic super-app shell.

## Feature inventory overview

| Area | Priority | Release boundary |
|---|---|---|
| Decision closure, environments, security, privacy, identity, audit, transaction data and observability | P0 | Foundation / all releases |
| Consumer onboarding/profile/address, localized home/catalog/search/detail/cart/checkout/activity | P1 | MVP, selected category only |
| Partner verification/profile/catalog/availability/order response | P1 | MVP, cohort only |
| Payment adapter, verified state transitions, reconciliation/refund controls | P0/P1 | MVP only after D-03/D-04/D-06 approval |
| Support/admin queue, scoped RBAC, order/payment lookup, audit | P0/P1 | MVP operational minimum |
| Dispatch/provider app | Conditional P1 | D-02 (2026-11-13) selects no provider-operated flow for phase A (pickup); revisit only for phases B/C |
| Reviews, promotions, loyalty, advanced analytics, richer partner/provider tooling | P2 | Marketplace/everyday expansion |
| Booking categories, family/child, health, events, AI task execution, new cities/countries | P2/P3 | Dedicated later gates |

## Exclusions and constraints

No feature assumes a named vendor, signed partner, approved commission, payment intermediary role, KUNDE fleet, district, transaction volume or launch date. Integration alternatives and costs must be evaluated before commitment. Features involving personal or regulated data are gated by D-07–D-10. See [open decision register](../product/PRD-1.1/23-assumptions-and-open-decisions.md).

