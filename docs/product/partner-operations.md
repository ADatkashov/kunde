# Partner Operations MVP (DEV pilot)

A KUNDE partner manages incoming Food/Grocery orders and bookings of its own restaurant/venue from the same Flutter app
(Profile → «Партнёрам» → «Заказы, записи и доступность»). Visible only to signed-in users whom the server reports as
staff of an APPROVED partner (ADR-018: `kunde.partner` scope + per-request membership check). DEV pilot, synthetic data only:
no real payments, providers or notifications; production readiness stays gated.

## Model (Flyway V20)

- `food_restaurants.partner_id`, `booking_venues.partner_id` (nullable). Rows **without** a partner keep the old behavior
  (Food: elapsed-time simulation; Booking: instant `DEV_MOCK` confirmation), so existing flows and smokes are unchanged.
- `food_orders.fulfillment_mode` = `PARTNER` (+ `partner_id`) for partner restaurants: no simulator, only the partner moves the status.
  `cancel_reason`, `cancelled_by` (CUSTOMER/PARTNER/SYSTEM); `food_order_events` gained `actor_type`, `actor_user_id`, `reason` (still append-only).
- Bookings at partner venues start as `PENDING` (`confirmation = PARTNER`) and **hold the slot**: the exclusion constraint
  `bookings_master_no_overlap` now covers PENDING/CONFIRMED/COMPLETED. New append-only `booking_events`; `cancelled_by`/`cancel_reason`.
  A PENDING request nobody answered expires at the start time (`CANCELLED` by SYSTEM, slot freed).
- `partner_catalog_events`: append-only audit of availability/stock/schedule changes (actor, entity, field, old/new).

## API (`/api/v1/partner/partners/{partnerId}/…`, partner token required, `Cache-Control: no-store`)

| Area | Endpoint | Notes |
|---|---|---|
| Food | `GET food/orders?scope=active\|history`, `GET food/orders/{id}`, `POST food/orders/{id}/status {status, reason?}` | State machine PLACED→ACCEPTED→PREPARING→ON_THE_WAY→DELIVERED; reject (CANCELLED) from PLACED/ACCEPTED/PREPARING needs a 3–300 char reason; response lists `allowedNext` |
| Food catalog | `GET/PATCH food/restaurants[/{id}]` (open), `GET/PATCH food/restaurants/{id}/dishes[/{id}]` (available, stockQty, clearStock) | Names/prices stay with the offering flow |
| Booking | `GET booking/bookings?scope=requests\|upcoming\|history`, `POST booking/bookings/{id}/action {CONFIRM\|REJECT\|CANCEL\|COMPLETE, reason?}` | REJECT (PENDING) and CANCEL (upcoming CONFIRMED) need a reason; COMPLETE after the start |
| Availability | `GET/PATCH booking/venues[/{id}]`, `…/services/{id}` (available), `…/masters/{id}` (active), `PUT …/masters/{id}/hours` | Hours change refused `409 SCHEDULE_CONFLICT` if a PENDING/CONFIRMED booking would no longer fit |

Rules: stranger/revoked staff → `404 PARTNER_NOT_FOUND` (existence hidden); unapproved partner → `403 PARTNER_NOT_APPROVED`; role not allowed
(Operator may process orders/bookings and toggle dish/service/master availability; venue/restaurant open and schedules need Owner/Manager) →
`403 PARTNER_ROLE_FORBIDDEN`; another partner's order/booking/dish → `404` (indistinguishable from missing); illegal move → `409
ORDER_TRANSITION_INVALID` / `BOOKING_TRANSITION_INVALID`; missing reason → `400 REASON_REQUIRED`.
**Idempotency:** repeating the request whose target is already reached returns `200` with the current state and writes no new event/audit row.
**Races:** order/booking rows are locked `FOR UPDATE` per transition (customer cancel vs partner accept resolves to one outcome); schedule edits take
`FOR UPDATE` on the master row while bookings take `FOR SHARE`; the DB exclusion constraint is the last line against double booking.
Customer side: `GET /food/orders/{id}` now returns `simulated=false`, `fulfillment`, `cancelledBy`, `cancelReason`, timeline `actor`/`reason`;
bookings return `PENDING` (cancellable by the customer) and `cancelledBy`/`cancelReason`. The app polls order/pending-booking status.

## Response window and alerts (D-05)

A new partner-managed order must be answered within `PARTNER_RESPONSE_TIMEOUT_SECONDS` (default 300 s). The partner API returns `respondBy` and `reminderAt`
(2 minutes after placing); the hub shows «Ответить до HH:mm» and turns it into a reminder. After the window the **system cancels** the order
(`cancelled_by = SYSTEM`, `cancel_reason = PARTNER_TIMEOUT`, payment voided, stock returned, SYSTEM event in history); it is applied lazily on every partner
read/transition and customer read (a late accept gets `409`). In the open app, a newly arrived order/booking request plays the system alert, a haptic tap and a banner
(first load is silent). No background push (no provider, D-11) and no scheduler: an order nobody reads stays `PLACED` in the table until the next read.

## Who sees the partner section

`PARTNER_FEATURES_ENABLED` builds show it only to partner staff; «Стать партнёром» appears to other users only when the build also sets `PARTNER_APPLY_ENABLED`
(workflow input `partner-apply`, default off).

## DEV pilot seed

`PARTNER_OPS_SEED_DEMO=true` (dev/local/test only; `PartnerOpsDemoSeeder`) creates two synthetic APPROVED partners owned by the allowlisted DEV numbers
`+77000000002` («Демо-партнёр KUNDE», linked to restaurant `partner-kitchen-demo` and venue `partner-salon-demo`) and `+77000000003`
(«Демо-партнёр Б», no assets; used to prove isolation). The customer in the scenario is `+77000000001`. Not seeded by migrations.

## Verification

`scripts/dev/partner_ops_smoke.py BASE_URL [CUSTOMER_PHONE]` (prints `SMOKE OK`) covers the whole scenario over real HTTP: access control
(customer 403, other partner 404, anonymous 401), order → accept → prepare → on the way → delivered with customer-visible statuses, replays, skipped step 409,
reject with reason, availability change blocking an order, booking request → hold → confirm → partner cancel → slot freed, reject, confirm, history after a session
refresh. Backend: `PartnerOperationsApiIntegrationTest` (15 tests) + existing suites; Flutter: `partner_hub_test.dart`.

## Limits

No background push/SMS (partner list polls every 10 s, customer screens every 4–5 s), no courier/payment/provider, no partner-side price/menu editing
beyond the existing offering API, no break/exception-day editor, no blocked-time slots, no multi-restaurant order merging, UI strings RU/KK/EN best effort
(KK to be reviewed).
