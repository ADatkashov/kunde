# 14 — Customer Experience Operations

## Service promise

KUNDE promises a clear view of what is available, the party responsible for fulfillment, exact price basis, current transaction state and a reachable support route. Do not promise universal category availability, exact ETA, refund timing or provider response unless operationally measured and contractually supported.

## Communication standards

| Event | Required message content | Timing/owner |
|---|---|---|
| Order/booking submitted | Reference, pending vs confirmed, next expected step | Immediately after persisted result; platform |
| Partner/provider accepted | Confirmed party, scope/time and status | Verified state event; platform |
| Delay/unavailable | What changed, last verified update, choices | As soon as event is verified; responsible operator |
| Cancellation | Actor, effective state, financial state separately | On state change; platform |
| Refund | Requested/pending/verified complete/failed, amount | On provider state; finance/payment integration |
| Support case | Case ID, owner/queue, next update expectation if known | On case persistence; support |

Use Kazakh/Russian for initial market; messages are concise, neutral and accessible. Do not notify customer of partner internal details, suspected fraud evidence, or another user’s data.

## Consistent experience with category-specific workflows

Shared patterns: discover → inspect terms → commit → monitor → resolve. Food uses cart; mobility uses route/dispatch; appointments reserve slots; home service may require quote; tickets require issuance. Common activity and support unify history without forcing one fulfillment state machine. Consumer can always distinguish “request received”, “provider confirmed”, “in progress”, “completed” and “payment/refund pending”.

## Recovery and retention

When service fails, prioritize truthful status, user options and financial safety over retention messaging. No dark patterns or repeated promotions during complaint/refund. Offer reordering/favorites only after issue is resolved and marketing preferences permit. Measure first-contact resolution, repeat contact, post-resolution satisfaction, successful fulfillment and trust-related cancellations together.
