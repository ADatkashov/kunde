# 23 — Assumptions and Open Decisions

Assumptions are recommendations to unblock specification, not approved facts. Assign a named owner and due date before the related production gate.

## Explicit assumptions

| ID | Assumption/recommendation | Validate with | Blocks |
|---|---|---|---|
| A-01 | Almaty is initial market; KZT is expected display/settlement currency. | Product, finance, legal | Checkout/payment launch |
| A-02 | Food ordering is the candidate first category, with grocery and mobility conditional. | Product/operations/partners | MVP category selection |
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
| D-01 | Which category and exact merchant/provider cohort launches first? What operational proof is mandatory? | Product + Operations | MVP scope lock |
| D-02 | Who provides delivery/dispatch: merchant, third party, KUNDE courier, or hybrid? | Operations + Partnerships | Fulfillment design |
| D-03 | Payment provider, supported methods, authorization/capture/refund semantics, settlement and reconciliation cadence? | Finance + Engineering + Legal | Transaction pilot |
| D-04 | Currency, taxes, fee display, commission, partner settlement terms and dispute allocation? | Finance + Legal | Partner contracts |
| D-05 | Consumer/partner/provider response SLAs and auto-timeout behavior? | Operations + Partners | Order/booking policies |
| D-06 | Category-specific cancellation windows, no-show treatment, refunds and partial fulfillment rules? | Product + Legal + Finance | Public terms |
| D-07 | Identity assurance and verification by user/partner/provider role? | Trust + Legal + Security | Account and partner launch |
| D-08 | Data residency, retention schedule, deletion exceptions, consent language and AI processor rules? | Legal + Privacy + Security | Production data |
| D-09 | Family guardian verification and child-data controls? | Legal + Product | Phase 3 |
| D-10 | Regulated health/pharmacy boundaries and review requirements? | Legal + Clinical/compliance owner | Phase 3 |
| D-11 | Which map, geocoding, messaging, analytics and AI integrations are approved? | Engineering + Procurement + Privacy | Technical architecture |
| D-12 | Exact performance, availability, RPO/RTO, load and incident response targets? | Engineering + Operations | Architecture sign-off |
| D-13 | Rating eligibility/moderation, promotion funding and eligibility policies? | Product + Trust + Finance | Growth rollout |
| D-14 | Admin separation of duties and refund approval thresholds/dual control? | Finance + Security | Admin pilot |
| D-15 | Public language set, translation owner and legal approval workflow? | Product + Localization + Legal | Almaty launch |

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

