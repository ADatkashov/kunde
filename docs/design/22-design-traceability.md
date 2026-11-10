# 22 — Design Traceability

This table maps every PRD 1.1 functional ID to UX output. IDs in ranges expand to each named ID. Stories/AC references point to `docs/product/PRD-1.1/03-user-stories.md` and `07-acceptance-criteria.md`; screen IDs are in 13. Components refer to 06; accessibility coverage is in 16 and 20. Requirements without a visible screen (e.g. payment reconciliation) map to role-restricted Admin/transaction states and are not omitted.

| Requirement IDs | Stories / AC | UX screens | Components / flow | UX rationale |
|---|---|---|---|---|
| AUTH-001, AUTH-002 | AUTH-001/002; AC-08/09 | C-01–04, P-01, D-01, A-01 | Phone input, OTP, session states; Identity flow | Verification, recovery and step-up are explicit; no account enumeration |
| USER-001, USER-002 | USER-001/002; AC-10/11 | C-14/15, C-29 | Input, address picker, permission state | Manual location alternative and reverification |
| USER-003, USER-004 | USER-003/004; AC-12/13 | C-29, C-33/34 | Switch, consent, privacy state | Marketing separate from transactional notice; deletion explains retention |
| FAM-001, FAM-002 | FAM-001/002; AC-14/15 | C-31, C-20, A-03 | Family grants, beneficiary selector | No inherited adult history; guardian authority required |
| HOME-001, HOME-002, HOME-003, HOME-004 | HOME-001–004; AC-01–04 | C-05 | Location chip, cards, banners, empty state | Personalization and promotion terms remain transparent |
| SEARCH-001, SEARCH-002, SEARCH-003 | EXP-002; AC-06/07 | C-07–09 | Search, filter, sort, map/list, stale state | Grouped results, no fabricated listings, canonical refresh |
| EXP-001 | EXP-001; AC-05 | C-06, C-10–13 | Category/business/service/product cards | Price basis, provider, service area and support are visible |
| FOOD-001, FOOD-002 | ORDER-001; AC-16 | C-11/12, C-16/17 | Merchant-scoped cart, price summary | Stock/options/substitutions reviewed before commit |
| MOB-001 | ORDER-003; AC-18 | C-21, C-26 | Mobility request, status timeline/map fallback | Pickup, destination, estimate expiry, assignment and timeout distinct |
| HOME-005 | EXP-003; AC-07 | C-13, C-20 | Quote component, confirmation dialog | Estimate separated from final accepted scope/price |
| HEALTH-001 | EXP-001; AC-05 | C-10/13/19/20 (disabled pending review) | Sensitive state and consent | No diagnosis; no orderable screen until legal/ops approval |
| CARE-001 | BOOK-001; AC-19 | C-13, C-19/20 | Staff/resource slot picker | Time slots and resources differ from product cart |
| FAMILY-003 | FAM-002; AC-15 | C-31, C-19/20 | Guardian/beneficiary control | Child information is minimized and parent-controlled |
| EVENT-001 | EXP-001; AC-05 | C-10/13, C-19/20 | Ticket/quantity/inventory state | Ticket issuance is distinct from payment success |
| AUTO-001 | BOOK-001; AC-19 | C-10/13, C-19/20/21 | Vehicle profile consent, quote, booking | Inspection estimate and extra-work approval are explicit |
| ORDER-001, ORDER-002 | ORDER-001/002; AC-16/17 | C-16–18 | Quote, idempotent confirm, payment state | Revalidate and prevent duplicate submit |
| ORDER-003 | ORDER-003; AC-18 | C-25/26 | Timeline, support, provider-unavailable state | Rejection/dispatch timeout has recovery path |
| BOOK-001, BOOK-002 | BOOK-001/002; AC-19/20 | C-19/20/27 | Hold timer, slot picker, reschedule/cancel review | Slot race, old booking preservation, policy display |
| PAY-001, PAY-002 | PAY-001/FIN-001; AC-21/33 | C-18/25/28, A-13/14 | Payment/refund status, immutable timeline | Only verified provider status advances financial state |
| ACT-001 | ACT-001; AC-22 | C-25–28 | Segmented activity list, detail, receipt | Order, booking and payment remain distinct |
| SUP-001 | SUP-001; AC-23 | C-35, A-18 | Case form, evidence, case timeline | Case-linked support; safe duplicate handling |
| PARTNER-001 | PARTNER-001; AC-28 | P-02–05, P-11–16, P-23, P-25, A-05/06 | Verification checklist, scoped catalog | Unverified business is not orderable |
| PARTNER-002 | PARTNER-002; AC-29 | P-07–10, P-17 | Queue, accept/reject, calendar, role grants | Timeouts, tenant/location scope and state version shown |
| PROVIDER-001 | PROVIDER-001; AC-30 | D-01–11, D-14/15 | Offer/task status, assignment revocation | Minimum task data and no stale completion |
| OPS-001, OPS-002 | OPS-001/002; AC-31/32 | A-03–12, A-15, A-17/18 | Case/purpose gate, moderation/appeal | Support, moderation and finance duties separated |
| FIN-001 | FIN-001; AC-33 | P-22, D-12, A-13/14/20 | Settlement status, reconciliation table | Mismatch is reviewed; no silent ledger edit |
| ADMIN-001 | ADMIN-001; AC-34 | A-01/21/22 | Role grants, audit, maker/checker | Privilege is scoped and break-glass visible |
| AI-001, AI-002, AI-003, AI-004, AI-005 | AI-001–004; AC-24–27/35 | C-22–24, A-19 | Source/result, draft preview, confirmation, task history | Information vs draft vs action distinct; no AI permission bypass |

## Accessibility and trace closure

All screen rows inherit requirements from accessibility spec 16 and QA 20. Specific high-risk controls (payment, location, cancellation, AI confirmation, family beneficiary, admin financial action) require keyboard/screen-reader focus and text equivalents. At handoff, every Figma frame must name its Screen ID and requirement; unrepresented requirement gets an explicit “no visible UI” explanation and corresponding operational state.
