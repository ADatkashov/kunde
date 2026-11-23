# Rides & Transport 1.0 — gap analysis against the reference design (2026-11-22)

Source: the 10-screen reference image requested by the owner. Audit is of `main` code, not documentation. Status: **PLAN — most items below are not yet built.** Update 2026-11-23: step 2 (Consumer restyle) is partly done on existing APIs: category hub (only city rides is available, others show «Скоро»), tariff cards (server price on the quoted class only), full-screen searching state driven by the real status, driver card, completed screen. Update 2026-11-23: Partner «KUNDE Taxi» (tabs Service/Fleet/Drivers, KPIs from the fleet endpoint; revenue, tariffs, zones and analytics shown as «Скоро») and Admin «Поездки — аналитика и управление» (KPIs, 7-day chart, status split, latest rides from `admin/rides/trips`; no revenue, city or type because the endpoint has none) are built on existing APIs. Still open: Minivan class, ETA per class, driver rating/contact, share link, promo and payment.

| Reference screen / feature | In code today | Gap | Needs |
| --- | --- | --- | --- |
| 1 Consumer home (logo, city, bell, search, 11-tile grid) | Home with categories, search panel, capability-driven tiles (`home_screen.dart`) | Visual redesign; some tiles (Flowers) have no product | Design tokens; show only real products, others "unavailable" under flags |
| 2 Rides hub (7 categories) | Single "Rides" screen (city taxi only) | Airport, intercity, car rental, courier (Delivery exists), business class (tariff class exists), trip planning: **no backend contract** | New products need owner approval; hub shows availability per category from capabilities |
| 3 Order taxi (map, A/B, tariffs, price/ETA, payment, promo) | Quote + order with ECONOMY/COMFORT/BUSINESS; map picker and route preview (maps PRs) | Minivan class, ETA per class, promo codes, payment choice. **Payments are blocked by `RidesConfiguration` until an approved provider exists** | MINIVAN tariff; promo domain; payment provider decision |
| 4 Searching driver (dark, animated) | Dispatch and status polling exist | UI only | Full-screen state driven by real status; no timer-faked assignment |
| 5 Driver found (map, driver, ETA, rating, plate) | Driver name/vehicle/plate, location polling, map panel | Driver rating (no ratings table), contact (phone not exposed), ETA to pickup | Ratings domain, masked contact, ETA via Maps route |
| 6 In trip (progress, share, support) | Status + support report | Distance travelled/remaining, share link (none) | Share-link domain (signed, expiring, scoped), live route progress |
| 7 Completed (fare, rating, review) | Status COMPLETED | Rating/review, receipt, payment confirmation | Ratings domain; payment out of scope until provider |
| 8 Partner "KUNDE Taxi" | Fleet endpoints (`RideFleet*`); Partner app has Delivery/Orders only | Partner UI for fleet, drivers, shifts, tariffs, zones, revenue, analytics | Partner Rides screens + org-scoped queries + RBAC |
| 9 Executor app | Online, offers, progress, history; Navigate (maps PRs) | Income, rating, payouts, shifts | Earnings read model, ratings |
| 10 Admin | Driver/vehicle review, trips, complaints (`RideAdminController`) | Dashboard with date/city/status filters, tariffs, zones, analytics | Aggregates over real tables |

## Principles
Maps supplies geometry, distance and typical time; **prices come from the backend tariff**; no fake revenue, ratings or payments; every new capability ships dark behind a backend flag; production is not enabled without an owner decision.

## Order of work (small PRs with tests)
1. Maps integration (in review/merged): routing provider, map picker + preview, driver/courier on map, Executor navigation.
2. Design tokens and Rides screens restyle (hub, order, searching, found, in trip, completed) on existing APIs.
3. Backend: ratings and reviews (migration, idempotent endpoint, aggregates), MINIVAN class, ETA to pickup.
4. Share-trip link (signed, expiring), masked contact.
5. Partner and Admin Rides screens over real aggregates.
6. Promo and payment: blocked on an approved payment provider.
7. Airport / intercity / rental / planning: separate PRDs and contracts; shown as unavailable until then.
