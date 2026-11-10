# KUNDE Product Documentation

## Baseline and change log

- **PRD 1.0** (`PRD-1.0.md`) is the original product vision and phased roadmap, preserved from the supplied source document.
- **PRD 1.1** (`PRD-1.1/`) translates that vision into functional behavior, operational boundaries, and testable requirements. It is a recommendation-level specification; decisions requiring partner, legal, payment, or architecture validation are explicitly identified in `23-assumptions-and-open-decisions.md`.
- **Change log:** 1.1 adds role-scoped access, category-aware order and booking lifecycles, payment integrity, failure recovery, screen inventory, AI authorization, analytics, and requirement traceability. It does not approve a payment vendor, launch all categories, or authorize autonomous paid actions.

## How to use

Read PRD 1.0 first, then `01-product-scope.md` and `23-assumptions-and-open-decisions.md`. Product, design, engineering, operations, and QA should use requirement IDs as the shared reference. A recommendation marked “proposed” needs a named owner and validation before production policy is fixed. Requirements marked P0 are the smallest viable Almaty launch slice; a feature is not launch-ready without operational supply, fulfillment, support, and payment coverage.

## PRD 1.1 index

| File | Contents |
|---|---|
| 01 | Scope and release boundaries |
| 02 | Personas and role definitions |
| 03 | User stories |
| 04 | User flows and recovery paths |
| 05 | Functional requirements and category behavior |
| 06 | Business rules |
| 07 | Acceptance criteria |
| 08 | Screen inventory |
| 09–11 | Order, booking, and payment lifecycles |
| 12 | Cancellation, refunds, and disputes |
| 13 | Permissions and access control |
| 14 | Notifications |
| 15 | Search and discovery |
| 16 | AI scenarios and authorization |
| 17 | Error and edge-case catalog |
| 18 | Localization |
| 19 | Analytics and events |
| 20 | Integration contracts |
| 21 | Priorities and phases |
| 22 | Non-functional acceptance criteria |
| 23 | Assumptions and open decisions |
| 24 | Requirements traceability |

## Conventions

- Requirement IDs are stable, unique identifiers. Do not reuse retired IDs.
- P0/P1/P2/P3 indicate priority; release phases are defined in document 21.
- “Must” is normative. “Proposed” is a product recommendation pending validation.
- `Order`, `Booking`, and `Payment` are separate records with linked identifiers; one may exist without the others during recovery.
- Times are stored as instants and displayed in the service location's time zone, unless a requirement explicitly says otherwise.
- No real provider, payment, SMS, map, or AI-vendor capability is assumed.
