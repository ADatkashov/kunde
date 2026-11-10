# 16 — KUNDE AI Scenarios and Authorization

AI is an interface to authorized KUNDE capabilities, not an independent actor. Pipeline: classify intent → retrieve least-privilege context → ask clarifying questions → present source-backed options → prepare versioned draft → obtain explicit confirmation when consequential → revalidate → execute allowed tool → report verified outcome. See also PRD 1.0 §7.

## Scenarios

| Scenario | Context/tools | Confirmation and success | Failure response |
|---|---|---|---|
| Dentist tomorrow after 17:00 | User-selected location, date/time, search health catalog/availability; no diagnosis context required | Show licensed/verified status as sourced, provider, slot and price; booking/payment requires explicit final approval | If no slot, report no availability and offer alternate times/providers; do not suggest medical diagnosis |
| Compare three cleaners | Location, service scope, availability, current quote/catalog and review data | Show comparable quote basis, included work, rating count and source; user chooses | If fewer than three eligible, explain count; never fabricate comparison |
| Grocery order | Selected store, catalog, saved address, cart and stock validation | Present exact lines, substitutions, fees and total; confirm before payment/order | Changed stock/price returns draft for review; payment ambiguity triggers status lookup |
| Family day plan | Explicit family shares, location, calendar/preferences only if granted, event/food searches | Present proposed itinerary and what data is shared; each paid reservation independently confirmed | Conflicting schedule asks user; no child data shared absent guardian scope |
| Schedule taxi | Pickup, destination, time and mobility catalog/estimate | Show fare estimate/expiry and pickup details; explicit request confirmation | No driver acceptance → explain timeout, release/compensate verified payment state |
| Cross-category plan | Permission-filtered availability across selected categories | Each component remains a separate proposed action; user confirms each consequential commitment | Report completed/pending/failed steps individually; never imply all-in-one booking |
| Reschedule appointment | Own/delegated booking, policy, availability and new slot hold | Show old/new time, price/fee and slot hold; confirm; old booking remains per rule | Slot taken → retain old booking where possible and offer alternatives |
| Explain order status | Own order and verified event timeline | Summarize current server-confirmed state and last update | If provider state unresolved, state “checking”; never claim delivery/completion without evidence |

## Confirmation contract

Confirmation screen/message binds `user`, `beneficiary`, `action`, provider, items/service, location/time, total/currency, policy, data-sharing scope, expiry and draft version. A plain “yes” is accepted only when it unambiguously follows the exact current proposal. Price/slot/beneficiary/provider changes invalidate consent and require a new review. No confirmation can authorize action beyond the user's underlying grants.

## Safety, privacy and operations

- Read tools can retrieve only current user-authorized data. Write tools use same API permission checks and state transitions as UI actions; payment ledger has no direct AI tool.
- AI distinguishes retrieved fact, estimate, recommendation, prepared draft and executed result. Responses include freshness/source where helpful.
- Ambiguity asks a focused question; conflicting preferences are surfaced, not silently resolved when material.
- Tool failure is retried only where idempotency permits. Partial completion has per-step status and recovery path.
- Sensitive health/child/location context is not retained or supplied to a model unless necessary, consented and covered by approved processing policy. Provider choice and data retention remain open decisions.
- Users can inspect/delete conversation history/context; transaction/audit evidence has separate lawful retention and is not reintroduced as conversational memory after deletion.
- Log tool name, authorization decision, draft ID/version, outcome, latency and cost; avoid full prompts, sensitive content and raw identifiers unless necessity/retention is approved.

## AI priority

Basic search/help and explanation are P1 for early MVP only if trustworthy catalog/tools exist. Multi-step preparation is Phase 4. Paid/consequential AI execution is future scope and must not be enabled until confirmation, audit, permission, compensation and monitoring controls pass release review.
