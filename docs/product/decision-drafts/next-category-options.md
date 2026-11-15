# Next user category after Food and Grocery — options and recommendation (DRAFT, owner decision needed)

Status: **proposal, not approved.** The roadmap ([04](../../roadmap/04-product-roadmap.md)) adds the next category only after "stable unit/ops evidence" and category-specific policy; booking/mobility flows (everyday services) need a booking/dispatch lifecycle and clear liability. Food and Grocery run as a synthetic DEV pilot on the shared commerce stack (cart quote, idempotent orders, mock payment, simulated fulfillment). No category below is approved; nothing here changes a decision status.

| Option | What it reuses | What is new | Main gate / risk | Effort to a phone-testable slice |
| --- | --- | --- | --- | --- |
| A. Convenience / gifts / flowers (commerce vertical) | Catalog, cart, orders, stock, substitutions, history | Content only (stores, products) | Low: same model as Grocery; needs real partner content later | Days |
| B. Home & beauty services booking (cleaning, barber) | Catalog, partners (ADR-018), addresses, history | **Booking lifecycle** (slots, provider acceptance, reschedule/cancel, no-show), provider calendar | Liability, provider verification, cancellation/refund rules (D-06 covers food only) | 1–2 weeks (new domain module + screens) |
| C. Pharmacy | Catalog, cart, orders, stock | Regulated goods rules (prescription, age, storage), health-adjacent data | Legal/privacy review required; P3 in the roadmap | Blocked until legal review |
| D. Taxi / rides | Auth, addresses, support | **Dispatch, driver app, maps, tariff, safety**, real-time tracking | Largest scope and liability; needs drivers/fleet model (D-02 excludes a KUNDE fleet) | Months |

## Recommendation

1. Next vertical: **B — a minimal home-services booking slice** (e.g. cleaning): choose a service → address → time slot → request → provider acceptance (simulated in DEV) → status/history/cancel. It matches the "Everyday services" stage, reuses identity/addresses/partners and gives the Super App a different interaction pattern than commerce.
2. If the owner prefers the fastest visible result, **A** can be added in days with content only, but it adds no new capability.
3. **C and D stay blocked** (legal review; dispatch and fleet model).

## Owner decisions needed to start B

- Is booking approved as the next category, and which first service (cleaning, barber, other)?
- Cancellation and no-show policy for DEV (proposal: free cancel until the provider accepts, then support).
- Provider model for the pilot (synthetic providers only until partners are signed).

## Independent work meanwhile (no decision needed)

KK/EN texts for Food/Grocery screens, photo pipeline once licensed images are supplied (the `image_url` field is ready), partner/admin tooling for stock and availability, accessibility pass (TalkBack) and device checks of V17 features.
