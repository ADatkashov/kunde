# KUNDE Booking MVP — barbershops (DEV pilot)

Status: implemented for DEV with synthetic data. **Not production.** Owner decision 2026-11-15: option B of [next-category-options](decision-drafts/next-category-options.md) is approved as the next category, first service **barbershops**; cleaning and other household services are expanded after this MVP. Payments stay off.

## Rules (owner)

Venue → service → master → free slot → confirmation. Bookings are stored in PostgreSQL. A master can never be double-booked for overlapping time. Free cancellation until the service starts. No real payments (pay on site). Synthetic venues, masters and schedules. The confirmation is a **DEV mock**, labelled as such. Food and Grocery are unchanged. No PROD deploy; the DEV deploy is agreed separately.

## Gates

`BOOKING_ENABLED` is off by default; `BookingGuard` aborts startup unless `KUNDE_ENVIRONMENT` is dev/local/test and consumer identity is on. `BOOKING_SEED_DEMO` loads 4 invented barbershops (9 masters, 6 services, weekly schedules incl. breaks and days off; idempotent by slug; no users or bookings). `GET /capabilities` reports `bookingEnabled`; the app shows «Услуги» only when it is true.

## Data (Flyway V18)

`marketplace.booking_venues/_services/_masters/_master_services/_working_hours` and `transactions.bookings`. Prices are integer KZT minor units; times are `timestamptz`, slots are computed in the venue zone (`Asia/Almaty`). **No double booking:** `EXCLUDE USING gist (master_id WITH =, tstzrange(starts_at, ends_at) WITH &&) WHERE status IN ('CONFIRMED','COMPLETED')` (extension `btree_gist`), plus a per-user advisory lock and an overlap check for the customer (one person cannot be at two masters at once). Verified by an API test and a direct-SQL test that the constraint itself rejects an overlapping insert.

## API (`/api/v1/booking`)

Public GET: `venues?category=BARBER`, `venues/{id}` (services, masters), `slots?venueId&serviceId[&masterId]&date` (15-minute grid inside working hours and outside breaks, 30-minute lead, 14-day horizon; without `masterId` each start time appears once with a concrete master).
Authenticated (own data only): `POST bookings` (+ `Idempotency-Key`; only an offered slot can be booked; `SLOT_UNAVAILABLE` / `SLOT_TAKEN` / `BOOKING_OVERLAPS_YOURS` / `TOO_MANY_UPCOMING_BOOKINGS`), `GET bookings`, `GET bookings/{id}`, `POST bookings/{id}/cancel` (only a confirmed booking that has not started, `BOOKING_NOT_CANCELLABLE` otherwise). Past confirmed bookings become `COMPLETED` on read.

## App

Home tile «Услуги» → «Барбершопы» (cleaning is shown as «Скоро») → venue → service → booking screen (master or any master, 14-day date strip, free times, comment) → «Записаться» → booking card. Orders tab has segments «Заказы» / «Записи»; bookings are restored from the server on every open and can be cancelled before the start. Skeleton loading, empty and error states with retry; Russian only.

## Mock / not included

Confirmation is automatic (`DEV_MOCK`: no venue or master acknowledgement, no notifications); payment on site, no provider; no real partners, venue-side schedule/booking screens, reschedule, reminders, reviews, photos (emoji tiles), per-master pricing or deposits. Cleaning and other services are not implemented.

## Checks

Local: `python3 scripts/dev/booking_smoke.py http://localhost:8080` (real HTTP: book, idempotent replay, slot disappears, double booking refused, restore after session refresh, cancel, slot freed) and backend/Flutter test suites; see [PROJECT_STATE](../../PROJECT_STATE.md) for the recorded results.
