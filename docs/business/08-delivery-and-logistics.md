# 08 — Delivery and Logistics

No owned fleet, courier pool or 3PL coverage is confirmed. Delivery must be enabled only where a real contracted fulfillment path exists.

## Model comparison

| Model | Benefits | Costs/risks | Launch suitability |
|---|---|---|---|
| KUNDE-owned/managed courier network | Service quality/control and unified dispatch | Fleet/driver ops, safety, insurance, hiring/classification, support and capital | Not recommended until demand density and legal operating model proven |
| Partner delivery | Low platform logistics burden, merchant local knowledge | Coverage/quality inconsistent; status data limited | Good initial option where merchant can fulfill reliably and responsibility is disclosed |
| Third-party logistics | Fast coverage and capacity access | Integration/dependency, per-delivery cost, data/quality control and support handoff | Pilot only after vendor coverage, lawful terms, status and incident SLA verified |
| Hybrid | Match merchant, partner and 3PL capacity by zone | More pricing/routing complexity and customer expectation risk | Recommended target only after each lane has proven capability |

## Zone and ETA design

Define service zones from partner operating hours/capacity and validated geospatial polygons, not a single city-wide radius. Check serviceability at browse and revalidate at checkout. Delivery quote includes components (merchant fee, carrier cost, customer fee/subsidy, applicable taxes) and expiry. ETA is a range based on current capacity and travel estimate, labeled estimate; do not promise exact time without contractual guarantee. Use time-of-day/weather/traffic only when a reliable approved source exists.

## Dispatch and route

Dispatch eligibility: role verified and active, zone/service type match, availability, capacity, vehicle constraints if relevant, assignment not already active. Ranking may consider distance, fairness/load and reliability under documented non-discriminatory policy. Accept/reject timer and retry sequence are configurable; no provider found leads to alternate option or cancellation/refund. Multi-order batching is deferred until delivery-time, food-safety, privacy and compensation effects are validated; each delivery remains separately traceable.

## Pickup, drop-off and proof

At pickup verify order reference and package count/condition. At drop-off use recipient confirmation, one-time code or other evidence only if lawful/practical; photo/signature requires privacy policy and consent. Failed delivery records reason: customer unavailable, address inaccurate, access issue, item restriction, safety or carrier failure. Contact customer through controlled channel, attempt configured retry, then return to merchant or safe hold only under contract; compensation/refund rule is disclosed.

## Almaty rollout recommendation

Start with merchant pickup or partner-delivered service in a small verified zone; add one contracted logistics lane after test deliveries and support runbook. Expand by zone and daypart only when partner/courier acceptance, on-time completion, cost/order, failed delivery, safety and support outcomes meet pilot gates. Do not claim live map tracking unless valid location events are available and approved.
