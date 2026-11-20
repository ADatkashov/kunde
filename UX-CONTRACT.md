# KUNDE mobile interaction contract

| Capability | Owner | Behavior and source | Verification |
|---|---|---|---|
| Authentication | AuthRepository / AppAuthGateway | ADR-015: system-browser code + PKCE, secure vault, serialized refresh/logout; no automatic contact linking | auth_repository_test.dart; auth_gateway_test.dart |
| Protected navigation | AuthScreen | Load /me before home; clear protected profile and in-memory draft on logout/401; reauthenticate explicitly | auth_screen_test.dart |
| Form | Material Form / TextFormField | ConsumerIdentityController validation, explicit save; no duplicate submit; keep draft on network failure | auth_screen_test.dart |
| Language | Material PopupMenuButton / ChoiceChip | RU/KK/EN; local welcome selection, profile preference committed only on save | auth_screen_test.dart |
| Feedback | AuthScreen semantic live region | Loading indicator, inline failure/retry, save success, partial provider logout warning | auth_screen_test.dart |
| CRUD | /me API and AuthScreen | Own profile only; version required; 409 preserves draft and requires explicit reload; cancellation/route changes ask to discard dirty edits | ConsumerIdentityIntegrationTest; auth_screen_test.dart |
| Scrollbar | Flutter Material ScrollBehavior | Platform-owned scrolling and scrollbars; safe areas and keyboard resizing | widget layout checks |

No billing, deletion, phone verification, legal consent or session administration
UI is introduced. Production readiness gates in ADR-015 remain separate from
development authorization. Test doubles exist only under mobile/test.

## Premium mobile surfaces (owner brief 2026-11-15)

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | Material Form / TextFormField | Existing identity and Food contracts | Profile, checkout | auth_screen_test.dart; food_flow_test.dart |
| Select/Listbox | Material PopupMenuButton / RadioGroup | Existing server capability and catalog values | Language, city, catalog sorting, checkout | kunde_shell_test.dart; food_flow_test.dart |
| Scrollbar | Flutter Material ScrollBehavior | DESIGN.md; platform behavior | Natural mobile scroll and safe areas | home_screen_test.dart; kunde_shell_test.dart |
| Toast | ScaffoldMessenger / semantic inline regions | Existing screen state owners | Error, success, session notice | auth_screen_test.dart; food_flow_test.dart |
| CRUD | Existing AuthRepository / FoodServices / BookingServices | docs/product/food-mvp.md; docs/product/booking-mvp.md; identity contracts | Existing operations only | food_flow_test.dart; booking_flow_test.dart; auth_screen_test.dart |

Five visible tabs preserve direct access to Profile. City selection currently
contains Almaty only; no unsupported city can be selected. Services checks
`bookingEnabled` before mounting the booking catalog, including entry from the catalog. AI, favorites, promos and Pay retain explanatory unavailable states.
The theme changes presentation only; order creation, quote, stock, cancellation,
substitution consent and session transitions retain their existing owners.

| Health booking | BookingApi / BookingFlowScreen | Каталог следует capability. Цена и условия показываются до записи. После неопределённого результата повтор использует тот же ключ. Перенос и отмена используют серверный статус. | Widget Health, BookingApiIntegrationTest, health_native_e2e.py |
