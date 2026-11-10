# 15 — AI Business Operations

AI is an assisted capability and operations co-pilot, not an autonomous commercial authority. Architecture 17 and PRD 1.1 §16 remain binding. All external actions use permission-checked domain APIs and audit trail.

| Capability | Business value / required data | Allowed actions | Human approval/restrictions and failure path |
|---|---|---|---|
| Customer assistant/search | Lower discovery friction; current catalog, location consent, preferences | Search, explain, compare; prepare drafts | User confirms paid/consequential step; stale search falls back to refresh |
| Recommendations | Improve relevant discovery; eligible behavior/catalog | Rank authorized listings and explain basis | No sensitive inference without approval; monitor bias and opt-out |
| Booking/order preparation | Reduce entry work; quote/availability/cart | Create nonbinding draft/hold | Exact user confirmation, revalidation; release hold if abandoned |
| AI support assistant | Faster agent lookup; case-scoped verified facts | Summarize and draft reply/options | Human agent sends consequential/disputed response; no refund/decision authority |
| Partner insights | Help stock/availability/service decisions; scoped aggregate business metrics | Explain trend, suggest hours/stock review | No unilateral price/availability changes; partner decides |
| Ops anomaly triage | Prioritize delayed, duplicate, fraud-risk or payout exceptions | Flag, group and summarize evidence | Human reviews restrictions, refunds, fraud/adverse actions; false positive appeal |
| Demand forecast | Staffing/zone planning from aggregated history | Forecast with confidence range | No automatic workforce/partner penalties; validate bias/seasonality |

## Controls

Role-scoped data, purpose limit, sensitive-data minimization, model/vendor approval, token/cost budgets, tool allowlist, prompt-injection handling, confirmation binding, explainable status, audit and task-level success metrics. Never write financial ledger, directly call payment provider, decide medical treatment, bypass role checks, determine legal liability or suspend/terminate without authorized human. On uncertainty or tool failure, state what is known and offer manual route. Human can inspect/override model recommendation; log decision and outcome without retaining unnecessary raw prompts.
