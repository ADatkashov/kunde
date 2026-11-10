# 22 — Business KPIs and Analytics

Each metric has a named owner, event source, reporting window and denominator definition. Targets are not approved. Any proposed threshold used in launch gate must be marked hypothesis and replaced with pilot evidence.

| Domain / KPI | Formula and source | Owner / caveat |
|---|---|---|
| Customer active users | Distinct eligible active consumer IDs in period; consented app/domain events | Product; define activity and exclude bots/internal test |
| Search-to-detail conversion | Distinct search sessions with eligible result detail / search sessions | Product; split no-results and partial search |
| Detail-to-transaction conversion | Completed orders/bookings / eligible detail sessions | Product; separate category and transaction type |
| Retention D7/D30 | Cohort users with qualifying activity on day window / cohort activated | Product; report order-repeat separately from app opens |
| Repeat order rate | Customers with ≥2 completed orders in cohort / customers with ≥1 completed | Growth; bookings separate |
| Customer satisfaction | Post-resolution/transaction survey responses and response rate | CX; response bias and accessible survey |
| GMV | Sum of qualifying consumer transaction value under finance metric policy | Finance; exclude/define tax, cancellations, refund adjustment and duplicate lines |
| Platform revenue | Recognized commission, fees/subscription/ad revenue under accounting policy | Finance; exclude pass-through funds and unearned fees |
| Take rate | Transaction platform revenue / GMV | Finance; present gross/net version explicitly |
| Orders/bookings | Count by created, accepted, completed, cancelled and refunded state | Operations; do not combine order and booking denominators |
| Partner activation/retention | Verified partners with first completed transaction / verified cohort; retained active partner cohort | Partnerships; define active threshold |
| Acceptance/fulfillment rate | Accepted / submitted valid; completed / accepted eligible | Operations; segment partner/provider/category and reason |
| Provider activity/earnings | Eligible providers completing task; gross and net settled earnings | Provider Ops/Finance; estimated vs paid separated |
| Delivery performance | Median/p90 submit-to-delivery time; late/failure rate / eligible delivery tasks | Logistics; use verified timestamps and promise definition |
| Refund rate | Refunded captured amount / captured amount; plus refund cases / completed transactions | Finance/CX; separate customer/partner/fraud reason |
| Payment failure/unknown | Verified failures and unknown age / payment attempts | Finance; unknown state is not failure |
| Support response/resolution | First human response and resolution distribution by priority | CX; median and p90, working hours stated |
| Dispute rate/time | Disputed transactions / completed transactions; time to adjudication | Trust/Finance; report provider chargebacks separately |
| Contribution margin | Revenue less attributable variable costs by order/customer/category/city | Finance; allocation policy explicit |
| CAC/LTV | Attributed acquisition spend/new activated customer; cohort expected contribution over horizon | Growth/Finance; LTV model confidence and payback shown |

## Event source and privacy

Use event taxonomy in PRD 1.1 §19 and reconciliation data from Architecture 21. PII, precise location, health, child and raw AI prompt do not enter broad analytics. KPI aggregates must suppress small cells that can re-identify a person. Finance-reported data is reconciled to immutable financial records before executive publication.

## Launch scorecard

For each category/city show demand, supply, conversion, acceptance, completion, delays, refunds, support, payment integrity, partner retention and contribution. No single GMV metric can override failed fulfillment, unresolved payment exceptions or negative unit contribution.
