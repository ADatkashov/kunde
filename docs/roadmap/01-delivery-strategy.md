# 01 — Delivery Strategy

## Approach

Deliver a modular marketplace in narrow, end-to-end slices. First establish decisions, contracts, and a deployable foundation; then prove one category's browse-to-fulfillment-and-finance loop in a controlled Almaty pilot. Keep domain modules in the recommended modular monolith until measured scale or independent ownership justifies extraction. Flutter and backend teams integrate against versioned OpenAPI contracts and design tokens.

Product delivery is risk-first: validate supply, fulfillment, transaction economics, customer support and legal constraints before broad feature development. Engineering delivery is trunk-based with reviewed changes, automated quality gates, feature flags, backward-compatible migrations and observable releases. Parallel work is appropriate for isolated design-system/mobile foundation, backend platform and operational decision closure; transactional client work must wait for stable API/domain contracts.

## Scope stages

| Stage | Outcome | Scope boundary |
|---|---|---|
| Foundation | Reproducible environments, contracts, identity/security baseline, data/migration discipline, telemetry and admin access | No real public transactions |
| MVP / closed pilot | One selected category and limited service zone; consumer discovery, order/booking path as applicable, partner workflow, support/admin, provider integration only if the fulfillment model requires it | No broad eight-category launch, autonomous AI, or assumed owned fleet |
| Initial production | Publicly available only in proven zones/hours with signed supply, support/finance/legal readiness and production SLO/incident gates | Expand volume conservatively; retain kill switches |
| Post-launch | Improve reliability, conversion, retention and unit economics; add categories one at a time | Evidence and operational capacity required |
| Full Super App target | Marketplace, services, lifestyle, AI and multi-city/country capabilities | Separate category, legal, data and operating gates |

## Quality, dependencies, prioritization

No feature enters implementation without a user outcome, requirement/story link, owned API/data contract, privacy/security review appropriate to its data, testable acceptance criteria, localized states, rollout/rollback plan and named operational owner. P0 means a blocker or critical control, not a license to start unsafe work. P1 is minimum pilot capability; P2 follows evidence; P3 is aspirational.

Track external dependencies as explicit decisions and adapter contracts. Do not build against a presumed payment, OTP, maps, messaging, AI, hosting or analytics vendor. Prefer fakes/sandbox contracts until procurement and legal review complete. Critical path is decision closure → transactional/fulfillment contract → foundation/security/data → order and payment state integrity → partner/admin/support operations → end-to-end pilot rehearsal → limited launch.

## Definition of Ready

- Approved user story and PRD requirement(s); no unresolved scope ambiguity for the increment.
- UX states and localization content are reviewed; API and data ownership are agreed.
- External/vendor/legal assumptions are identified with owner and fallback.
- Acceptance, negative-path, security/privacy, telemetry and rollout criteria are measurable.
- Dependencies are completed or represented by a stable, testable contract.

## Definition of Done

See [23-definition-of-done.md](23-definition-of-done.md). In short: accepted behavior, reviewed code/config, required tests passing, security/privacy and accessibility addressed, telemetry/support docs present, migrations compatible, and release/rollback evidence recorded. A task marked complete does not imply release approval.

## Release strategy

Promote the same version through internal, QA, alpha, closed beta, limited production and wider production, with explicit gates. Use feature flags and server-side category/zone controls. Keep API and database changes expand-migrate-contract; mobile clients may remain on older supported APIs. Hotfixes use the same review and observability controls with an expedited, recorded path.

## Not in first launch

All eight categories, provider/fleet network unless the selected fulfillment contract requires one, family/child and regulated health flows, cross-category bookings, loyalty/promotions, advanced analytics, AI task execution, multi-country localization and microservice extraction. These are deferred by risk and operational readiness, not by lack of long-term intent.

