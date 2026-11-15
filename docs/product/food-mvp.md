# KUNDE Food MVP (DEV pilot)

Status: implemented for DEV with synthetic data. **Not production.** Owner priority 2026-11-15: a working user scenario before further infrastructure.

## Scope and gates

Authority: D-01 (Food Ordering, Almaty), D-02 (phased hybrid fulfillment), D-03/D-04 (DEV pilot: pay on receipt, KZT, one final price, 0% commission), D-05/D-06 (response and free-cancel rules), ADR-015 (own phone OTP), ADR-018. [ADR-014](../architecture/adr/ADR-014-unavailable-catalog-default.md) stays in force by default: Food is **off** unless `FOOD_ENABLED=true`, and the backend refuses to start with it outside `KUNDE_ENVIRONMENT=dev|local|test` or without `CONSUMER_IDENTITY_ENABLED=true` (`FoodGuard`). Production keeps `marketplaceEnabled=false`.

| Area | Real | Mock (explicit, DEV only) |
| --- | --- | --- |
| Restaurants, menus, options | PostgreSQL (`marketplace.food_*`, Flyway V15), public read API | Content is a synthetic seed (`food/demo-catalog.json`), 8 invented restaurants flagged `synthetic`; no photos (emoji tiles), no ratings |
| Cart | Server-side pricing (`/food/cart/quote`); the client sends ids only | Cart lines live in the app and are persisted locally |
| Checkout / orders | PostgreSQL (`transactions.food_orders/_items/_events`), idempotent (`Idempotency-Key`), snapshots of names, prices and address | — |
| Payment | — | `TEST_CARD` (marked paid, **no card data is ever collected**) and `CASH_ON_DELIVERY` (pay on receipt) |
| Fulfillment | Status history is persisted | Restaurant acceptance, cooking and delivery are **simulated by elapsed time** (defaults 20/45/120/240 s, `app.food.simulation.*`) |
| Delivery zone | Saved address is snapshotted | No serviceability check (DEV: any saved Almaty address) |

## API (all under `/api/v1/food`)

Public GET: `restaurants`, `restaurants/{id}` (sections → dishes → option groups), `search?q=`.
Authenticated (consumer scope, own data only): `POST cart/quote`, `POST orders` (+ `Idempotency-Key`), `GET orders`, `GET orders/{id}`, `POST orders/{id}/cancel` (only while `PLACED`, D-06), `GET orders/{id}/repeat`.
Order status: `PLACED → ACCEPTED → PREPARING → ON_THE_WAY → DELIVERED` or `CANCELLED`. Money is integer KZT minor units (tiyn). Errors use the shared `ApiError` shape; see `openapi/kunde-api-v1.yaml`.

## DEV seed and enabling

`FOOD_SEED_DEMO=true` loads the synthetic catalog once at start (idempotent by restaurant slug; existing rows are never modified; no users or orders are created). Env: `FOOD_ENABLED`, `FOOD_SEED_DEMO`, plus phone auth and consumer identity as in [phone-otp-auth](../identity/phone-otp-auth.md).

Local end-to-end check against a running backend: `python3 scripts/dev/food_smoke.py http://localhost:8080 +77000000001` (needs the number in `AUTH_DEV_OTP_ALLOWED_PHONES`).

## Not included

Real payments (D-03/D-04 production model), real restaurant/partner order handling and courier logistics, notifications, promo codes, ratings, photos, serviceability zones, restaurant-side order screens. These stay gated by their own decisions.
