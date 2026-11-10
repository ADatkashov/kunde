# 19 — Analytics and Business Events

Event collection supports product and operations decisions while minimizing personal data. Each event has `event_id`, `event_name`, `occurred_at`, `schema_version`, pseudonymous `actor_id` where justified, session/correlation IDs, locale, app version and coarse market/service area. Do not place raw query text, full address, phone, health data, child data, payment credentials or conversation content in general analytics.

| Event | Trigger | Required domain properties | Purpose / privacy |
|---|---|---|---|
| registration_started/completed | Auth flow milestones | method class, locale, result | Funnel; phone excluded |
| authentication_result | Verified sign-in result | result class, device class | Reliability/security; no OTP |
| search_submitted | Search submitted | category scope, filter flags, coarse region | Search use; query omitted or separately consented/minimized |
| search_results_viewed | Results rendered | result count, latency, partial flag | Relevance/performance |
| search_result_selected | Listing opened | listing type/category, rank | Discovery; pseudonymous listing ID |
| category_discovered | Category entered | category ID/source | Adoption |
| business_viewed / service_viewed | Detail shown | category, listing ID, source | Funnel; no sensitive free text |
| cart_created / checkout_started | First cart/checkout action | merchant ID, item count, subtotal band | Conversion; no item notes with personal data |
| payment_attempted / payment_state_changed | Payment command/verified state | amount/currency, method class, result class, correlation | Finance/health; provider refs stay restricted |
| order_placed / order_state_changed | Persisted transition | order ID, category, state, fulfillment type | Fulfillment; actor scope |
| booking_created / booking_state_changed | Persisted transition | booking ID, category, state, lead time band | Capacity; avoid reason free text |
| cancellation_requested / completed | Request and outcome | actor class, reason code, policy version, outcome | Policy and cancellation |
| refund_requested / state_changed | Refund lifecycle | amount/currency, reason code, verified state | Finance; restricted dataset |
| review_submitted | Eligible review accepted | rating, category, moderation state | Quality; review text separately controlled |
| support_case_opened / resolved | Case transition | category, reason code, resolution time | Support; content excluded |
| ai_conversation_started | New conversation | entry point, locale, feature version | Adoption; no prompt text |
| ai_task_execution | Tool execution begins/ends | tool class, authorization result, duration, outcome, cost band | Safety and cost; no sensitive payload |
| ai_task_completed | Verified task completion | step count, completion class, confirmation flag | AI outcome; correlate task only |

## Governance

Document owner, purpose, retention, access class and deletion/aggregation policy for each production dataset before launch. Separate restricted operational/financial events from general analytics. Suppress or aggregate low-volume data that could identify a person. Event emission must not block core transaction; use durable event/outbox and reconcile event loss. Metric definitions for DAU, retention, conversion, fulfillment and refund rates must be consistent with PRD 1.0 §14 and published before executive reporting.
