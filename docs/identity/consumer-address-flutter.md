# ADA-76 / TASK-010 — Flutter saved addresses

The existing backend `/api/v1/me/addresses` API is used directly by the authenticated consumer profile.

- List owner-scoped addresses with the backend's `serviceable` flag.
- Create an address with a label, formatted address, and manually entered WGS84 latitude/longitude.
- Delete an address only after confirmation, sending its optimistic `version`; a 409 triggers a fresh list.
- Treat missing/false serviceability as **not confirmed**, never as an available delivery zone.
- Do not persist address details in insecure device storage; use the existing bearer-token session client and no client-side address cache.
- Validate coordinates locally; the backend remains authoritative. No map SDK, geocoding, routing, delivery promise, or zone coverage claim is introduced.
- RU/KK/EN labels are available; production UX/accessibility and real device validation remain required.

Tests: `mobile/test/features/identity/address_repository_test.dart` exercises owner routes, coordinate validation, conflict handling and bearer auth. Run `cd mobile && flutter analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`.
