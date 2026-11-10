# 26 — Business Traceability

PRD 1.1 has 46 functional IDs. This matrix links the primary business/operational decisions to product, architecture, UX, workflow, metric and accountable owner. Full requirements: `../product/PRD-1.1/24-requirements-traceability.md`; screen inventory: `../design/13-screen-inventory.md`.

| Requirements | User flow / UX | Architecture/data owner | Business rule/process | KPI / accountable owner |
|---|---|---|---|---|
| AUTH-001/002, USER-001 | Registration/profile; C-01–04/C-29 | IAM/User | Partner/customer verification scopes; privacy playbook | Activation/security incidents; Product + Security |
| USER-002, HOME-001–004 | Address/search Home; C-05/C-14/15 | User/Geo/Catalog/Pricing | Service-area and promotion readiness | Search-to-detail, serviceability; Product/Ops |
| USER-003/004, AI-005 | Settings/privacy; C-29/C-33/34 | User/Privacy/AI | Consent and deletion workflow | Consent coverage, deletion completion; Privacy |
| FAM-001/002, FAMILY-003 | Family beneficiary booking; C-31 | User/Family/Booking | Guardian/delegation review | Unauthorized access incidents; Legal/Product |
| SEARCH-001–003, EXP-001 | Search/category/detail; C-06–13 | Search projection/Catalog | Only active verified supply displayed | Search conversion/no-result/availability; Marketplace |
| FOOD-001/002, ORDER-001, ORDER-002, ORDER-003 | Food cart/payment/tracking; C-16–18/C-25/26 | Order/Catalog/Finance | Merchant response, stock, substitution, fulfillment | Acceptance, completion, contribution; Category Ops |
| MOB-001, PROVIDER-001 | Mobility and assignment; C-21/D-05–11 | Mobility/Provider/Geo | Provider lane, safety and assignment expiry | Acceptance/completion/incident; Logistics |
| HOME-005, CARE-001, BOOK-001/002 | Quote and booking; C-13/C-19/20/27 | Pricing/Booking | Quote approval, atomic slot, cancellation policy | Slot conflicts, completion, no-show; Category Ops |
| HEALTH-001, EVENT-001, AUTO-001 | Category-specific detail/booking | Catalog/Booking/Finance | Separate legal/issuer/inspection gates | Availability, disputes, approval; Compliance/Ops |
| PAY-001/002, FIN-001 | Payment/refund; C-18/C-28/A-13/14 | Finance ledger/payment adapter | Verified provider event, reconciliation, settlement | Unknown payment, payout accuracy, CM; Finance |
| ACT-001, SUP-001 | Activity/support; C-25/35/A-18 | Order/Booking/Support | Case authorization and customer communication | Contact rate, resolution time, satisfaction; CX |
| PARTNER-001/002 | Onboarding/order processing; P-02–17/A-05/06 | Partner/Catalog/Order | Verification, category activation, SLA | Partner activation/retention/acceptance; Partnerships |
| OPS-001/002, ADMIN-001 | Support/moderation/admin; A-03–25 | Support/Trust/Platform | Scoped access, adverse-action appeal and audit | Backlog, moderation appeal, access anomalies; Ops/Trust |
| AI-001–005 | Search, preview, confirmed action; C-22–24/A-19 | AI task + domain APIs | No direct payment/ledger action; human control | Completion/tool success/cost/complaints; AI Product |

## Gaps carried forward

- D-01 launch category/cohort, D-02 fulfillment ownership, D-03 provider/funds flow, D-04 commission/tax/settlement and D-05 SLAs remain open in PRD 1.1 §23.
- Legal character of KUNDE marketplace/payment role, consumer contract party, VAT/accounting treatment and category licenses require counsel.
- Actual city demand, supply, pricing, partner fees, provider capacity, customer acquisition cost and contribution margin are unknown.
- Refund/no-show/late cancellation windows, support staffing and incident response coverage require contract/operations approval.
- No specific partner, courier fleet, 3PL, payment, OTP, maps or AI provider is confirmed.
- International city/country readiness cannot be inferred from Almaty pilot; local legal/tax/data diligence required.

Implementation work should not begin for a category until its product requirement, design screen/state, data/API boundary, commercial owner, operational playbook, legal gate and KPI definition all have owners and acceptance criteria.
