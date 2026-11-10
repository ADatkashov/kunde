# 14 — UI States and Edge Cases

Every data-bearing screen has an explicit state contract. State is described with icon/shape, heading, explanatory copy and action; color is supplementary. Never replace “pending/unknown” with “success” or “failed” until the server/provider confirms it.

| State | Presentation and sample source copy | Action / behavior |
|---|---|---|
| Initial | Show stable shell and useful entry point; no spinner before request starts | User can begin search or select category |
| Loading | Skeleton matching card/form layout; top-level progress only for longer waits | Mark region busy; do not announce every skeleton row |
| Success | Persisted result, explicit status and next step | Success toast only for noncritical confirmation; transaction details show state |
| Empty | Heading “Nothing here yet”; explain why and offer action | Clear filters, select location, browse supported service |
| Error | “We couldn’t load this. Try again.” plus context | Retry preserves safe input; correlation stays hidden but available to support |
| Offline / no internet | Banner “You’re offline. Reconnect to continue.” | Cached data labeled stale; consequential action disabled; query state after reconnect |
| Permission denied | Explain purpose and provide manual route | “Location is off. Enter an address to see nearby services.” No repeated system prompt |
| Location unavailable/out of area | State selected city/address; “This address is outside this service area.” | Edit/select address; do not silently relocate |
| Session expired | “Please sign in again. We’ll check your last action.” | Reauthenticate; look up idempotency key before resubmitting |
| Payment pending/unknown | “We’re checking your payment. Please don’t pay again yet.” | Poll/query with backoff; support link; no second charge action |
| Payment failed (verified) | “Payment didn’t go through.” | Try another approved method only after verified failure; keep cart if safe |
| Booking unavailable | “That time was just booked.” | Refresh slots; choose another; release expired hold |
| Provider unavailable | “This provider is unavailable right now.” | Offer validated alternatives or support; no false live availability |
| Order cancelled | Show who cancelled, reason if shareable, effective time and refund separately | Continue to refund detail/support; never hide original order timeline |
| Refund pending | “Your refund is being processed.” | Show amount, date requested and support route; never label completed early |
| Partial fulfillment | List completed and unresolved items separately | Offer accepted recovery choices; no whole-order success claim |
| Unsupported category | “This service isn’t available here yet.” | Choose supported category or update area; avoid inactive checkout path |
| AI uncertain/partial | State what was found, not found and completed | Ask one clarification, retry read, or offer manual path; no action claim without verified result |

## State persistence and recovery

Transient UI state can reset on process restart; safe drafts persist only if privacy-reviewed. For every timed-out mutation, client checks current transaction by its original idempotency key before retry. Session expiry retains no secret in navigation history. Stale search/card data cannot authorize checkout, booking or cancellation. Error pages preserve query/filter/form fields except secret values. Offline provider actions may queue only if role/task policy explicitly allows and conflict resolution is visible.

## Screen-reader announcements

Announce state change once in a polite live region; urgent transaction/security result may use assertive announcement where justified. Focus moves to an error summary after failed form submission, not to every field in sequence. Pending transitions use text (“Checking payment”), not a spinner alone.
