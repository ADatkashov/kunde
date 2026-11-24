# KUNDE Partner — standalone Flutter application (DEV)

Mobile app for owners, managers and operators of restaurants and service businesses (ADR-019). It talks to the existing
Partner Operations API only; the **backend remains the authority** for access, roles and every status transition.
The embedded partner hub in `mobile/` is untouched until parity is verified on a phone.

## Run

```bash
cd partner_app
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter run --dart-define=API_BASE_URL=https://kunde-backend-ty81.onrender.com/api/v1/ --dart-define=DEV_OTP_HINT=true
```

`API_BASE_URL` must be an `https://` URL ending in `/`. `DEV_OTP_HINT` shows the synthetic demo code hint and must never be set for
a production build.

## Structure (`lib/`)

| Path | Role |
|---|---|
| `core/` | Design tokens/theme (Material 3, deep-green brand, light/dark), RU/KK/EN strings (`strings.dart`), error text, formatting |
| `data/` | `PartnerApi` (timeouts, GET retry, one 401 refresh+replay, UTF-8), typed `models.dart`, `PartnerOperations` (existing endpoints only) |
| `auth/` | `PartnerSession`: OTP, refresh token in secure storage, single-flight rotation, expiry vs. offline handling |
| `app/` | `AppController` (restore session, partner discovery/choice, revoked access), `OpsStore` (shared data, actions, foreground alerts), settings |
| `features/` | login, partner gate, shell (bottom navigation), orders, bookings, business, profile |
| `widgets/` | skeletons, empty/error states, status chips, dialogs |

## Rules enforced in code and tests

- No literal user-visible strings in widgets; all text comes from `S` (RU/KK/EN). Raw JSON, ids, status codes and stack traces are never shown.
- Actions offered to the user come from the server (`allowedNext`, `allowedActions`). Unsupported backend operations are not faked.
- POST actions are never retried automatically and are guarded against double taps; idempotent GETs retry on connectivity errors.
- A stored session survives restarts and short outages; it is cleared only when the server rejects the refresh token or the user signs out.
- Foreground alerts poll only while the app is visible, with back-off; no background service or push (see `docs/product/partner-app.md`).

Release/APK: see `docs/product/partner-app.md`.
