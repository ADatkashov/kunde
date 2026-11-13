# 23 — Assumptions and Open Decisions

Assumptions are recommendations to unblock specification, not approved facts. Assign a named owner and due date before the related production gate.

## Explicit assumptions

| ID | Assumption/recommendation | Validate with | Blocks |
|---|---|---|---|
| A-01 | Almaty is initial market; KZT is expected display/settlement currency. | Product, finance, legal | Checkout/payment launch |
| A-02 | Food ordering is the first category (approved in D-01, 2026-11-13); grocery and mobility stay conditional and disabled for real transactions. | Product/operations/partners | Exact partner cohort |
| A-03 | Merchant response deadlines, payment capture timing and cancellation fees are configurable per contract/category, not globally fixed. | Operations, finance, legal | Order/refund policy |
| A-04 | One cart is one merchant and one fulfillment context. | Product | Checkout scope |
| A-05 | Phone OTP is desired authentication but provider and fallback are unselected. | Security, product, vendor | Registration launch |
| A-06 | Provider review/verification is required before orderable supply. Exact KYC/verification depends on category and law. | Trust, legal, operations | Partner launch |
| A-07 | Payment provider success will be verified via provider events and/or status lookup; exact capability unknown. | Finance, engineering, vendor | Payment architecture |
| A-08 | User requests for family member require explicit relationship/authority record. | Legal, product | Family/child services |
| A-09 | AI provider-neutral orchestration is required, with no paid autonomous execution in initial MVP. | Product, security, privacy | AI rollout |
| A-10 | Web/mobile client can consume versioned REST API; precise technical architecture remains a later artifact. | Engineering | Technical architecture |

## Decisions required

| ID | Decision | Owner(s) | Needed by |
|---|---|---|---|
| D-01 | **PARTIALLY APPROVED 2026-11-13** — category (Food Ordering) and market (Almaty) approved; exact merchant cohort, pilot zone and mandatory operational proof remain open. See [D-01 record](#d-01--initial-category-and-pilot-market). | Product + Operations | MVP scope lock |
| D-02 | **APPROVED 2026-11-13** — phased hybrid fulfillment for Food Ordering: A pickup, B merchant-managed delivery, C third-party logistics; no KUNDE courier fleet at start. See [D-02 record](#d-02--food-ordering-fulfillment-and-delivery-model). | Operations + Partnerships | Fulfillment design |
| D-03 | Payment provider, supported methods, authorization/capture/refund semantics, settlement and reconciliation cadence? | Finance + Engineering + Legal | Transaction pilot |
| D-04 | Currency, taxes, fee display, commission, partner settlement terms and dispute allocation? | Finance + Legal | Partner contracts |
| D-05 | **APPROVED 2026-11-13** — Food Ordering restaurant response: 5 min deadline, 2 min reminder, auto-timeout; other SLAs per D-12. See [D-05 record](#d-05--restaurant-response-sla-and-order-timeout). Original question: consumer/partner/provider response SLAs and auto-timeout behavior? | Operations + Partners | Order/booking policies |
| D-06 | **APPROVED FOR PRODUCT RULES 2026-11-13** — free cancel before acceptance, no invented penalties, explicit consent for substitutions; refunds/penalties stay gated by D-03/D-04/legal. See [D-06 record](#d-06--cancellation-refund-and-partial-fulfillment-policy). Original question: category-specific cancellation windows, no-show treatment, refunds and partial fulfillment rules? | Product + Legal + Finance | Public terms |
| D-07 | **APPROVED FOR INITIAL ROLE MODEL 2026-11-13** — partner roles Owner/Manager/Operator + KUNDE Administrator, manual verification; proofing method, documents and KYC provider remain open. See [D-07 record](#d-07--partner-identity-and-verification). Original question: identity assurance and verification by user/partner/provider role? | Trust + Legal + Security | Account and partner launch |
| D-08 | Data residency, retention schedule, deletion exceptions, consent language and AI processor rules? | Legal + Privacy + Security | Production data |
| D-09 | Family guardian verification and child-data controls? | Legal + Product | Phase 3 |
| D-10 | Regulated health/pharmacy boundaries and review requirements? | Legal + Clinical/compliance owner | Phase 3 |
| D-11 | Which map, geocoding, messaging, analytics and AI integrations are approved? | Engineering + Procurement + Privacy | Technical architecture |
| D-12 | Exact performance, availability, RPO/RTO, load and incident response targets? | Engineering + Operations | Architecture sign-off |
| D-13 | Rating eligibility/moderation, promotion funding and eligibility policies? | Product + Trust + Finance | Growth rollout |
| D-14 | Admin separation of duties and refund approval thresholds/dual control? | Finance + Security | Admin pilot |
| D-15 | Public language set, translation owner and legal approval workflow? | Product + Localization + Legal | Almaty launch |

## D-01 — Initial Category and Pilot Market

**Status:** PARTIALLY APPROVED — category and market approved by Product Owner, 2026-11-13.

**Decision owner:** Product Owner.

### Approved decision

KUNDE will launch its first consumer service category as **Food Ordering**, with **Almaty, Kazakhstan** as the initial geographic market.

KUNDE remains a universal everyday-life Super App. Food Ordering is the first implementation and market-validation category, not a restriction on the long-term product vision.

The architecture must preserve the ability to introduce additional service categories through existing platform contracts and approved roadmap phases.

### Pilot approach

The initial rollout follows a controlled, phased approach:

1. Internal technical validation using synthetic data and transactions.
2. Limited operational pilot with verified restaurant partners and invited users, subject to launch gates.
3. Geographic and partner expansion after operational acceptance.

### Proposed pilot cohort — not yet approved

- Target: 8–12 restaurant partners.
- One compact geographic pilot zone within Almaty.
- Initial invited test cohort: 50–100 users.
- Mix of everyday lunch, fast-casual, local cuisine, cafés and bakeries.

Exact restaurant identities, pilot zone, user cohort size and operational commitments remain subject to separate confirmation.

### Mandatory constraints

- No production orderability before required partner verification and operational readiness.
- No assumption that KUNDE operates its own courier network.
- No real payment collection without approved financial and payment-provider decisions.
- No invented cancellation fees, commissions, settlement terms or refund rules.
- No use of real personal data without applicable privacy and security approvals.
- Non-launch categories remain disabled for real transactions until their own gates are satisfied.
- Synthetic development and testing may continue independently of production approvals.

### Dependencies and remaining decisions

D-02 through D-15 remain unchanged and are not implicitly approved by this decision.

D-01 is approved for category and market selection. Exact partner cohort and operational proof remain open until verified.

### Implementation impact

Engineering may proceed with Food Ordering category-specific development and tests consistent with accepted architecture and existing task dependencies.

TASK-017 and related catalogue/partner tasks may be reassessed for technical readiness. No task should be marked fully completed without its acceptance evidence.

## D-02 — Food Ordering Fulfillment and Delivery Model

**Status:** APPROVED

**Decision date:** 2026-11-13

**Decision authority:** KUNDE Product Owner

**Initial market:** Almaty, Kazakhstan

**Initial category:** Food Ordering (D-01)

### Approved decision

KUNDE adopts a **phased hybrid fulfillment model** for Food Ordering.

#### Phase A — Restaurant Pickup

The first implementation supports customer pickup from a verified restaurant.

- The customer selects a restaurant and its available offerings.
- The customer selects pickup as the fulfillment method.
- The restaurant receives and processes the order.
- The customer receives confirmed order status and pickup instructions.
- Pickup availability and readiness must be grounded in verified restaurant data.
- KUNDE does not assign or dispatch couriers in this phase.

#### Phase B — Merchant-Managed Delivery

After the pickup workflow is validated and the relevant operational and legal conditions are met, KUNDE may enable delivery performed by the restaurant or its contracted delivery personnel.

- The merchant is responsible for fulfillment under approved contractual terms.
- Delivery eligibility and service area are configured per merchant.
- Delivery charges and estimates must come from verified merchant contracts or integration data.
- KUNDE displays only delivery states supported by real evidence.
- Live courier GPS tracking must not be claimed without an actual supported integration.

#### Phase C — Third-Party Logistics

KUNDE may integrate external logistics providers after approval of integration contracts, data processing, pricing, service levels, incident handling and reconciliation requirements.

- Providers are integrated through versioned adapters.
- Provider assignment, cancellation, tracking and failure handling must be explicit.
- Provider availability must be verified.
- No logistics provider is implicitly approved by this decision.

### Excluded from the initial scope

KUNDE will not operate its own courier fleet during the initial launch phase.

First-party courier recruitment, fleet management, payroll and dispatch operations are not part of the initial Food Ordering pilot.

This exclusion does not prohibit future reconsideration through a separate approved product decision.

### Architectural requirements

- Preserve the existing KUNDE modular-monolith architecture.
- Separate order lifecycle from fulfillment lifecycle.
- Support fulfillment methods through explicit, versioned contracts.
- Keep pickup, merchant delivery and third-party delivery capabilities independently configurable.
- Preserve idempotency, auditability, authorization and failure handling.
- Never infer a successful delivery from a successful payment or order acceptance.
- Keep unsupported fulfillment methods disabled.

### Implementation authorization

Engineering may implement the pickup fulfillment contract, configuration, validation, persistence, API boundaries and synthetic tests consistent with existing approved architecture.

Merchant-managed delivery and third-party logistics may be designed for future compatibility, but real integrations and orderability require their respective acceptance gates.

### Remaining decisions

D-03 through D-15 remain unchanged.

In particular, this decision does not approve:

- Payment provider or payment collection.
- Taxes, commissions or settlement rules.
- Order response deadlines and operational SLAs.
- Cancellation penalties, refunds or no-show fees.
- Partner identity verification policy.
- Data residency or retention policy.
- External logistics providers.
- Production launch.

### Roadmap impact

Reassess TASK-019, TASK-020, TASK-029 and TASK-030 against their full acceptance criteria and dependencies.

Only work directly authorized by this decision may be unblocked. Tasks requiring other decisions remain blocked or partially in progress, as appropriate.

D-02 is approved for the fulfillment model. Actual production operation remains subject to separate readiness evidence.

## D-05 — Restaurant Response SLA and Order Timeout

**Status:** APPROVED — Product Owner, 2026-11-13. **Scope:** Food Ordering pilot, Almaty (not automatically grocery, mobility, bookings or other categories).

### Restaurant confirmation

1. A restaurant has **5 minutes** to accept or reject a submitted order.
2. A reminder is generated **2 minutes** after submission if the order remains unanswered.
3. With no valid restaurant response within 5 minutes the order automatically transitions to a terminal timeout/rejection outcome.
4. A late restaurant acceptance cannot reactivate a timed-out order.
5. The customer receives an accurate order status and appropriate notification.
6. Duplicate submissions, callbacks and retries must not create duplicate orders or duplicate financial operations.
7. A restaurant marked unavailable must not accept new orders.
8. The restaurant supplies the preparation-time estimate; KUNDE must not present an unverified estimate as confirmed.

### Technical requirements

- 5 minutes / 2 minutes are the initial Food Ordering defaults; values must be configurable and versioned for future partner/category policies.
- The server is authoritative for deadlines and state transitions; timeouts and acceptance are concurrency-safe and idempotent; all state changes are auditable.
- Delayed workers and unavailable notification providers must not invalidate the authoritative deadline.

### Remaining gates

Production monitoring, escalation ownership and broader operational SLOs remain subject to D-12 and operational readiness.

## D-06 — Cancellation, Refund and Partial Fulfillment Policy

**Status:** APPROVED FOR PRODUCT RULES — Product Owner, 2026-11-13.

### Before restaurant acceptance

1. The customer may cancel before restaurant acceptance without a cancellation penalty.
2. An order that expires without restaurant confirmation is automatically rejected or cancelled and must not be fulfilled as if accepted.
3. Payment authorization, capture or refund consequences follow separately approved payment-provider and finance contracts.

### After restaurant acceptance

1. Cancellation is evaluated against the disclosed, versioned category/merchant policy and the verified preparation state.
2. No automatic cancellation penalty is permitted without approved legal terms and a valid applicable policy; where policy or legal approval is absent the system must not invent or collect a fee.
3. Disputed or exceptional cases are routed to an authorized support process.

### Partial fulfillment and substitutions

1. Restaurants must not silently substitute unavailable items.
2. Any change in items, quantities or total price requires explicit customer approval before commitment; the customer may reject it.
3. If fulfillment becomes impossible the order enters a defined failure, cancellation or support resolution path.
4. Partial refunds and financial adjustments require verified provider capabilities and approved accounting rules.

### Technical requirements

- Order and payment lifecycles remain separate; transitions are versioned, authorized, auditable and idempotent.
- Customer approval is recorded with the applicable order/quote version.
- Concurrency and retry handling prevent duplicate cancellations or financial actions; unsupported refund and penalty operations remain disabled.

### Remaining gates

D-03/D-04, legal review of consumer-facing terms, settlement and refund processing are not approved by D-06.

## D-07 — Partner Identity and Verification

**Status:** APPROVED FOR INITIAL ROLE MODEL AND VERIFICATION APPROACH — Product Owner, 2026-11-13.

### Initial roles

- **Restaurant Owner:** manages the restaurant within authorized scope, permitted staff access and business settings (subject to verification and audit controls).
- **Restaurant Manager:** manages menu, availability and order processing within assigned permissions; no automatic access to financial administration or platform-wide controls.
- **Restaurant Operator:** views and processes assigned restaurant orders; cannot manage ownership, staff privileges or platform policies.
- **KUNDE Administrator:** reviews partner verification and operational status within assigned platform permissions; no unrestricted access to financial operations, sensitive information or other administrative functions.

### Verification

1. Every restaurant passes verification before being enabled for real orders; initial verification may be manual by authorized KUNDE personnel.
2. Verification status and supporting evidence are auditable.
3. Unverified, suspended or rejected partners are not publicly orderable.
4. Each staff member has an individually attributable identity; permissions are scoped to the authorized restaurant and role; access is revocable.
5. Privileged actions require appropriate authorization and audit records.

### Technical requirements

- Use existing KUNDE identity and authorization boundaries; no second identity architecture without an approved ADR.
- Enforce role and tenant/partner isolation on the backend (never UI-only); reject unauthorized or cross-partner access.
- Keep identity, verification status and business permissions separate; use explicit state transitions for verification and suspension.

### Remaining gates

Exact identity-proofing method, legally required verification documents, sensitive-document retention and production identity-provider readiness need Trust, Legal, Privacy and Security review. No KYC provider or external verification service is approved.

## D-05/D-06/D-07 — Decision boundaries and roadmap impact

D-01, D-02, D-05, D-06 and D-07 are approved within their recorded scopes; D-03, D-04, D-08–D-15 are unchanged. These decisions do not authorize: real payment collection; production refunds or settlement; cancellation penalties; unapproved identity or OTP providers; processing real sensitive verification documents without privacy controls; public production launch; bypassing security, CI or operational gates.

Reassess TASK-015/016/017 (partner), TASK-021/022 (order lifecycle) and TASK-027/028 (cancellation/refund, still limited by payment and legal gates). Implementation may proceed on approved product logic and independently testable components; production enablement requires separate readiness evidence.

## Contradictions resolved by recommendation

1. PRD 1.0 describes a broad eight-category vision but says not all categories launch initially. Resolution: all eight share taxonomy and platform contracts; only operationally ready categories are orderable.
2. “One payment experience” could imply one universal transaction workflow. Resolution: common payment abstraction with distinct category order/booking/dispatch workflows and separate transaction lifecycles.
3. “AI task execution” could be read as autonomy. Resolution: AI can prepare; explicit version-bound confirmation and platform authorization are required for consequential action; no direct ledger access.
4. Family functionality could imply owner-wide access. Resolution: explicit per-member grants; adult privacy and child/guardian controls remain distinct.
5. A successful payment response could be mistaken for completed order. Resolution: verified payment and order persistence are separate; compensate and reconcile on handoff failure.

## Risk register

| Risk | Impact | Mitigation / launch gate |
|---|---|---|
| Insufficient supply/fulfillment | Orders fail, customer trust loss | Pilot cohort proof, readiness checklist and incident owner |
| Payment ambiguity/orphan order | Duplicate charge or lost order | Idempotency, verified webhooks/query, compensation, reconciliation |
| Overbroad staff/admin access | Privacy/fraud harm | Scoped grants, audit, separation of duties, access reviews |
| Category policy mismatch | Disputes/refund liability | Legal-approved category policy/version surfaced before commitment |
| AI hallucinated availability/action | User harm and false commitment | Tool-grounded responses, freshness, confirmation and verified outcome |
| Child/health data mishandling | High privacy/regulatory impact | Defer launch pending specialist review and access restrictions |
| Localization errors | Invalid consent/price comprehension | Human review of critical Kazakh/Russian flows |

