# 03 — MVP Definition (Almaty)

## Product decision

Recommended pilot: one operationally proven, high-frequency category in a limited, measured service zone. Food ordering in Almaty is the approved first category and market (D-01, partially approved 2026-11-13; see [PRD 1.1 §23](../product/PRD-1.1/23-assumptions-and-open-decisions.md)). The exact merchant cohort, pilot zone, hours and operational proof remain open under D-01. Grocery, mobility and all other categories stay disabled until separately approved and proven.

## Customer journey

1. Register through the approved identity flow (phone OTP is only a preference until provider, fallback and verification controls are selected); accept approved privacy/terms and choose language.
2. Set or select a validated address/service area. Do not promise service outside the configured zone.
3. Browse localized categories/offerings, search the available catalog, inspect partner, item/service details, availability, full price and fulfillment/cancellation terms.
4. Submit one merchant-scoped cart/request. Confirm the final amount and payment/fulfillment conditions before commitment. Prevent duplicate submission through idempotency.
5. See persisted order state and truthful status updates. If real-time integration is unavailable, show last-updated state, not fabricated tracking.
6. Contact human support from the order; see cancellation/refund status and an understandable history.

## Partner and operations journey

Verified, contracted cohort receives onboarding and a usable catalog/availability workflow, can accept/reject or update work within agreed SLAs, and can report fulfillment status. KUNDE staff can search the order, view an auditable status/payment timeline, triage exceptions, contact parties, and execute only policy-authorized cancellation/refund actions with any required dual control. Daily financial reconciliation and incident escalation are staffed before real transactions.

Provider UI is not a default MVP requirement. It is conditional on D-02: if a separate provider pool executes fulfillment, provider verification, availability, task acceptance, status, support and payout controls are required before the pilot.

## Payments, fulfillment, cancellation

The exact provider, funds flow, authorization/capture, refund/settlement policy and tax/fee display are **not specified yet**. Do not launch real payments until D-03/D-04/D-06 are approved, signed terms and legal review exist, sandbox and production readiness are documented, webhook/status verification and idempotent reconciliation pass, and refund/dispute rehearsal succeeds. If no compliant payment path is ready, run a non-transactional internal/closed usability pilot only; do not represent it as a real marketplace MVP.

Fulfillment may be merchant pickup, partner delivery, contracted dispatch or another approved model. Do not imply live courier tracking unless reliable provider events exist. Cancellation windows, timeout, partial fulfillment, no-show and refund rules must be category-specific, approved and visible before the user commits.

## Minimum launch infrastructure

Consumer Flutter app; Spring Boot modular backend; relational transactional database and versioned migrations; partner workflow (responsive web or agreed tool, selected during foundation); minimal admin/support console; identity and scoped authorization; approved payment/fulfillment adapters; localization; backups/restore evidence; logs/metrics/traces/alerts; feature flags/category-zone kill switch; support runbooks, on-call owner, reconciliation and incident process.

## MVP acceptance / exclusions

Acceptance: a pilot user can complete the approved happy path and recover from rejection, timeout, duplicate request, payment uncertainty, cancellation and support escalation; partner and operations states agree; no duplicate financial effect; reconciliation matches provider evidence; serviceability and final price are explicit; localization and consent reviewed; critical security/legal/operational gates signed. Full criteria live in releases and DoD.

Excluded: all-category launch, family/child, health/pharmacy, broad home services, events, loyalty, paid autonomous AI, international expansion and unapproved provider/fleet operations.

