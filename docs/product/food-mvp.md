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

## Grocery MVP (same DEV pilot, same gates)

Grocery reuses the Food catalog, server-side cart pricing, idempotent orders, mock payment, simulated fulfillment and history instead of a second stack. Flyway V16 adds `vertical` (`FOOD` default, `GROCERY`) to `marketplace.food_restaurants` and `transactions.food_orders`: a store is a restaurant row, a product is a dish row (options optional, e.g. fat content). API: `GET /food/restaurants?vertical=GROCERY`, `GET /food/search?q=&vertical=GROCERY`; the default vertical stays `FOOD`, an unknown one is `400 VERTICAL_INVALID`. Orders carry `vertical`. Seed `food/grocery-demo-catalog.json`: 4 invented stores, 45 products in KZT (one deliberately out of stock). The app opens it from the Home category «Продукты» (only when the server enables the marketplace); the Orders tab lists food and grocery orders together.

### Grocery completion (Flyway V17)

- **Weighed goods:** dish `unit` is `PIECE` or `KG`. For `KG` the price is per kg and quantities are **grams** in 100 g steps from 100 g to 5 kg (`FOOD_QUANTITY_INVALID` otherwise); line total = `round(price * grams / 1000)`, enforced by a DB check as well as the server. The app shows `1,5 кг` / `/ кг` prices and steps by 100 g.
- **Stock:** `stock_qty` (pieces or grams, NULL = not tracked). The quote refuses more than the stock (`FOOD_STOCK_INSUFFICIENT`); placing an order reserves stock with a conditional update (a race for the last units fails cleanly with 409); cancellation returns it. The catalog exposes `maxQuantity`/`stockQty`, the app shows «Осталось N» and caps the stepper.
- **Substitutions (customer consent only):** per line `NONE` (default), `ANY_SIMILAR` or `CHOSEN` (up to 5 products of the same store and unit; `GET /food/dishes/{id}/alternatives` lists candidates). When the simulated store starts preparing, a product that is no longer available is replaced only if the customer allowed it, otherwise the line is removed; a replacement is never charged above the original unit price. Order lines carry `fulfillmentStatus` (`OK`/`SUBSTITUTED`/`REMOVED`), `replacedByName`, `finalLineTotalMinor`; the order carries `hasChanges` and `finalTotalMinor`; an order whose every line is removed is cancelled with the payment voided. The app shows replaced/removed lines and «Итого с учётом изменений».
- **Photos:** `image_url` (HTTPS only, nullable) exists on stores and products and the app renders it with an emoji-tile fallback. **No photos are bundled or seeded**: licensed photo assets must be supplied by the owner; until then tiles are illustrations.
- **Catalog UX:** restaurant/store filters (open now, cuisine, sort by delivery time/fee), «В наличии» filter inside a menu, skeleton loading.
- Seed sync: existing synthetic DEV rows get units/initial stock (and the old `"..., 1 кг"` names are normalized) without touching prices or availability.

Not included: barcodes, age-restricted goods rules, per-store delivery slots, real store integrations, partial refunds beyond the mock payment status, KK/EN texts for Food screens (Russian only), real photos.

## Manual verification status

Owner report (2026-11-15): the Release APK from run 43734913344 (`58cf20a`, Food + Grocery MVP) was installed on a real Samsung phone, checked and "everything works". That is the only manual confirmation; no detailed scenario list, TalkBack or other devices were reported. V17 features (weighed goods, stock, substitutions, filters) are **not yet** manually verified.
