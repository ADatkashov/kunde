# 13 — API Architecture and Examples

## Contract conventions

Base `/api/v1`; HTTPS; JSON; OpenAPI; access tokens from selected OIDC-compatible identity system. `Idempotency-Key` required on creates and money/state mutation; `If-Match`/version on transition. Cursor pagination; allowlisted filter/sort; RFC3339 timestamps; currency + integer minor units. Errors: `{ "error": {"code":"...","message":"safe text","correlationId":"...","retryable":false,"details":[]} }`. Do not return secrets or reveal inaccessible resource existence. Commands are named actions, not arbitrary status PATCH. Version `/v2` only for incompatible contracts; additive fields must be tolerated.

## Registration and login

```http
POST /api/v1/auth/challenges
{"phone":"+7XXXXXXXXXX","purpose":"SIGN_UP","locale":"kk-KZ"}
```
```json
{"challengeId":"ch_01...","expiresAt":"2026-11-10T12:05:00Z","resendAfterSeconds":45}
```
```http
POST /api/v1/auth/sessions
{"challengeId":"ch_01...","code":"<user-entered>"}
```
```json
{"accessToken":"<short-lived-token>","expiresIn":900,"refreshToken":"<rotating-secret>","user":{"id":"usr_...","status":"ACTIVE"}}
```
Codes are never logged; production transport is TLS; challenge response avoids account enumeration.

## Profile, address and discovery

```http
GET /api/v1/me
PATCH /api/v1/me
{"displayName":"Aruzhan","locale":"kk-KZ"}
POST /api/v1/me/addresses
{"label":"Home","addressText":"...","location":{"lat":43.24,"lon":76.91},"instructions":"..."}
GET /api/v1/search?q=cleaning&category=home&addressId=addr_...&sort=availability&cursor=...
```
Address response:
```json
{"id":"addr_...","label":"Home","serviceArea":{"id":"area_...","eligible":true},"version":3}
```
Search response:
```json
{"items":[{"type":"SERVICE","id":"svc_...","businessId":"biz_...","name":"Home cleaning","price":{"kind":"QUOTE","currency":"KZT","minorUnits":null},"availability":"CHECK_REQUIRED","updatedAt":"2026-11-10T11:58:00Z"}],"nextCursor":null,"partial":false}
```

## Cart and order

```http
POST /api/v1/carts
{"businessId":"biz_...","fulfillment":"DELIVERY","addressId":"addr_..."}
POST /api/v1/carts/cart_.../items
{"productId":"prd_...","quantity":2,"options":[]}
POST /api/v1/orders
Idempotency-Key: 7dd...
{"cartId":"cart_...","quoteId":"qte_...","paymentMethodRef":"pm_...","expectedQuoteVersion":4}
```
```json
{"orderId":"ord_...","status":"PENDING_PAYMENT","payment":{"id":"pay_...","status":"PROCESSING"},"total":{"currency":"KZT","minorUnits":845000},"version":1}
```
`GET /api/v1/orders/{id}` returns authorized timeline, verified payment/refund state and next action. Status transitions use explicit command routes and idempotency/version checks.

## Booking and rescheduling

```http
POST /api/v1/bookings/slot-holds
{"serviceId":"svc_...","resourceId":"res_...","startsAt":"2026-11-11T12:00:00Z","timeZone":"Asia/Almaty"}
POST /api/v1/bookings
{"holdId":"hold_...","beneficiaryId":"usr_...","quoteId":"qte_..."}
POST /api/v1/bookings/bkg_.../reschedule
{"newHoldId":"hold_..."}
```
```json
{"bookingId":"bkg_...","status":"PENDING_CONFIRMATION","holdExpiresAt":"2026-11-10T12:02:00Z","version":1}
```

## Payment, refund and notifications

```http
POST /api/v1/payments/pay_.../confirm
{"returnReference":"provider-return-ref"}
POST /api/v1/payments/pay_.../refunds
Idempotency-Key: refund-ord-...-1
{"amount":{"currency":"KZT","minorUnits":250000},"reasonCode":"MISSING_ITEM","orderItemId":"itm_..."}
GET /api/v1/me/notifications?cursor=...
PATCH /api/v1/me/notification-preferences
{"marketingPush":false,"transactionalPush":true}
```
```json
{"refundId":"rfd_...","status":"PENDING","amount":{"currency":"KZT","minorUnits":250000}}
```
Client cannot mark payment confirmed/refunded; verified provider webhook/query is authoritative.

## AI conversation and action execution

```http
POST /api/v1/assistant/conversations
{"locale":"ru-KZ"}
POST /api/v1/assistant/conversations/cnv_.../messages
{"text":"Find a dentist tomorrow after 17:00"}
POST /api/v1/assistant/tasks/task_.../confirmations
{"draftVersion":3,"confirmation":"CONFIRM"}
```
```json
{"taskId":"task_...","status":"AWAITING_USER_CONFIRMATION","draft":{"version":3,"action":"CREATE_BOOKING","providerId":"biz_...","slot":"2026-11-11T12:30:00Z","total":{"currency":"KZT","minorUnits":150000},"expiresAt":"2026-11-10T12:02:00Z"}}
```
Confirmation is not a general authorization token; server rechecks role, price, slot and policy. Full async completion can be queried and optionally streamed by SSE after auth.

## Edge/API gateway

Gateway handles TLS, request limits, coarse rate limiting, routing and correlation ID. Fine-grained authorization stays in domain modules. Avoid storing long-lived user state in gateway.
