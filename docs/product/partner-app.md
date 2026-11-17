# KUNDE Partner app (standalone, DEV)

Status: DEV pilot. Synthetic data only; no PROD, real payments or push providers. Source: `partner_app/`. Architecture: ADR-019.

## What the app does (all through existing Partner Operations API)

| Area | Behavior | API |
|---|---|---|
| Sign-in | DEV phone OTP, restore after restart, expiry/offline handling, logout, partner choice | `auth/otp/*`, `auth/token/refresh`, `auth/logout`, `GET partner/partners` |
| Orders | Tabs New / In progress / Completed (paged history), details (items, totals, address, comment, timeline), accept/prepare/hand over/complete/reject with reason, reply countdown | `food/orders` (`scope`, `limit`, `offset`), `POST food/orders/{id}/status` |
| Bookings | Requests / Upcoming / History (paged), date and status filters, details, confirm/reject/cancel (reason)/complete | `booking/bookings`, `POST booking/bookings/{id}/action` |
| Business | Restaurants and venues with open state (read-only in this step) | `food/restaurants`, `booking/venues` |
| Alerts | In-app sound/haptic/banner for new orders and requests while the app is open | polling of two list endpoints (20 s, back-off to 2 min, foreground only) |

Transitions are decided by the backend (`allowedNext` / `allowedActions`); roles: `OWNER`, `MANAGER`, `OPERATOR` are returned by `GET partner/partners` and enforced by the server (`PARTNER_ROLE_FORBIDDEN`).

## Known API gaps (not faked in the UI)

- No aggregated metrics endpoint (revenue, counts per period). Dashboard values are derived only from lists already returned and labelled as such; a `GET partner/partners/{id}/stats?period=` contract is requested.
- No customer name/phone for orders and bookings (only an opaque reference), so "customer details" are not shown.
- No restaurant working-hours endpoint (only `open` toggle); venue working hours exist per master (`PUT …/masters/{id}/hours`).
- No staff-management endpoints for the app (grant/revoke exist only in `PartnerService`).
- No dish deletion, photos or option groups; no customer-slot listing for partners (slots are a customer endpoint).
- No push provider (D-11). A push plan (FCM device-token registration endpoint, server-side sender, per-partner topics, quiet hours) must be approved before implementation; foreground alerts are the supported mechanism now.

## Reliability rules

Timeouts 20 s; GET retried twice on connectivity/502/503/504; one token refresh + replay on 401; POST never retried; per-record busy guard; last good data kept on failure with an offline banner; a conflict refreshes lists.
