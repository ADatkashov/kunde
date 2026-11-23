# KUNDE Booking MVP — barbershops (DEV pilot)

Status: implemented for DEV with synthetic data. **Not production.** Owner decision 2026-11-15: option B of [next-category-options](decision-drafts/next-category-options.md) is approved as the next category, first service **barbershops**; cleaning and other household services are expanded after this MVP. Payments stay off.

## Rules (owner)

Venue → service → master → free slot → confirmation. Bookings are stored in PostgreSQL. A master can never be double-booked for overlapping time. Free cancellation until the service starts. No real payments (pay on site). Synthetic venues, masters and schedules. The confirmation is a **DEV mock**, labelled as such. Food and Grocery are unchanged. No PROD deploy; the DEV deploy is agreed separately.

## Gates

`BOOKING_ENABLED` is off by default; barbershops (`BARBER`) additionally need `BEAUTY_ENABLED` (owner decision 2026-11-23, see [Beauty & Care](beauty-care.md)); when it is off the barbershop catalog, slots and new bookings answer `404 BEAUTY_DISABLED` while history and cancellation stay available; `BookingGuard` aborts startup unless `KUNDE_ENVIRONMENT` is dev/local/test and consumer identity is on. `BOOKING_SEED_DEMO` loads 4 invented barbershops (9 masters, 6 services, weekly schedules incl. breaks and days off; idempotent by slug; no users or bookings). `GET /capabilities` reports `bookingEnabled`; the app shows «Услуги» only when it is true.

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

## Category architecture and Home services — cleaning (owner decision 2026-11-15, DEV)

User-facing categories are life needs, not technical modules: Food, Groceries, Rides, Delivery, **Home services («Дом и быт»)**, **Beauty («Красота»)**, Health, Auto, Leisure; «Все сервисы» is a common catalog, not a business category. Booking stays one internal mechanism (same API, PostgreSQL, slots, overlap protection, statuses, history, cancellation) reused by barbershops (category `BARBER`, under Beauty) and cleaning (category `CLEANING`, under Home services). No Booking module per category.

- **App:** Home tile «Красота» → «Барбершопы» (venue → service → master → slot → confirm, unchanged); tile «Дом и быт» → «Уборка» (type → address → area → estimated price → date/free time → request). The Services tab is the «Все сервисы» catalog listing both. Cleaning is not shown under Beauty and barbershops not under Home. Orders → «Записи» shows both kinds with their own marks; cancel label is «Отменить заявку» for cleaning.
- **Extension (Flyway V19):** `booking_services.price_per_sqm_minor/min_area_sqm/max_area_sqm` (price = call-out `price_minor` + per-m² price × area, area range enforced by the DB); `transactions.bookings.category/address_text/area_sqm` (existing barbershop bookings default to `BARBER`, no address/area — backward compatible). The server always computes the price; the app only previews it with the same formula. A cleaning crew is a synthetic "master"; crews cannot be double-booked (same exclusion constraint). Duration is fixed per cleaning type (no area-dependent duration yet).
- **API:** `GET /booking/venues?category=CLEANING`; `POST /booking/bookings` accepts optional `addressText` and `areaSqm`: cleaning requires an address (≥5 chars) and an area within the type's range (`ADDRESS_REQUIRED`, `AREA_INVALID`, `AREA_NOT_APPLICABLE` → 400); barbershop bookings reject them (`DETAILS_NOT_APPLICABLE`). Booking view adds `category`, `addressText`, `areaSqm`.
- **DEV data:** one synthetic company «KUNDE Уборка (демо)», types «Поддерживающая / Генеральная / После ремонта» (demo prices in tenge: call-out + per m², 20–150 m²), three synthetic crews. Demo prices are not real offers; no payment; free cancellation until the start.
- **Localization:** RU/KK/EN for category names, barbershop and cleaning flows, statuses, errors, history and cancellation (`booking_strings.dart`); the fixed demo catalog names are translated client-side, any other server text is shown as sent. Venue descriptions/bios stay as sent by the server (Russian).
- **Not included:** other Beauty/Home services (hair salon, manicure, plumber, electrician, repairs, assembly), reschedule, partner-side crew handling, real payments.

## Переключатель пилота «Дом и быт»

`HOME_SERVICES_ENABLED` по умолчанию выключен. Для запуска пилота требуются явное окружение `local`, `dev` или `test` и `BOOKING_ENABLED=true`. При разрешении окружением действующий Admin API переключателей управляет `HOME_SERVICES` с грантом `ADMIN_GRANTS` и аудитом. `GET /api/v1/capabilities` сообщает эффективное состояние в `homeServicesEnabled`.

При выключении сервер отклоняет запросы каталога уборки, карточки и слотов, а также создание новых заявок. История, отмена существующей заявки владельцем и получение результата идемпотентного повтора остаются доступны. Каталог и запись в барбершоп используют прежний флаг `BOOKING_ENABLED`. Синтетическое наполнение справочника управляется отдельно через `BOOKING_SEED_DEMO`.
