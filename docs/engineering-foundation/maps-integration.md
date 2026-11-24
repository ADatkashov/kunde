# KUNDE Maps Platform integration

Companion to [ADR-020](../architecture/adr/ADR-020-kunde-maps-platform-integration.md) (PROPOSED) and the kunde-maps
[ADR 0007](https://github.com/ADatkashov/kunde-maps/blob/main/docs/architecture/decisions/0007-kunde-maps-sdk-and-ecosystem-integration.md).

## What is wired (all behind flags, internal environments only)
| Area | Where | Flag |
| --- | --- | --- |
| Road routing and address search for Rides quotes and Delivery quotes | `kz.kunde.maps.KundeMapsRideRouting` implements `RideRouting` | `MAPS_ENABLED` (+ `MAPS_ROUTING_URL`, `MAPS_SEARCH_URL`) |
| Capability for clients | `GET /api/v1/capabilities` -> `mapsEnabled` | follows `MAPS_ENABLED` |
| Active-trip route endpoints for the assigned driver / courier | `GET /executor/rides/trips`, `GET /executor/deliveries` (`pickup`, `destination`) | Rides / Delivery executor flags; none for finished trips |
| Consumer Taxi and Delivery: map picker, route preview, driver/courier on the map | `mobile/lib/features/maps`, `rides`, `delivery` | `mapsEnabled` and the product flag |
| Executor: Navigate for Taxi trips and Delivery shipments | `mobile/lib/features/executor/driver_navigation_screen.dart` | `mapsEnabled` |

A screen shows map UI only when `mapsEnabled` is true; with it off, every flow is the previous list-based one.

## Rules
- Maps supplies distance, typical time (no traffic) and geometry. **The price is always computed by the Rides/Delivery tariff.**
- The Flutter apps use the pinned `kunde_maps_sdk` git tag from kunde-maps; no map or routing code is copied here.
- Provider failure -> HTTP 503 `RIDES_ROUTING_UNAVAILABLE` / `DELIVERY_ROUTING_UNAVAILABLE`, never a fallback price. "No road" -> 422.
- Coordinates and address queries are not logged. Drivers/couriers receive pickup/destination only while the trip is active.
- Navigation runs in the foreground (the Executor screen open); there is no background location service for navigation yet.
- Production enablement and the Maps Platform capacity need a separate owner decision and deployment approval.

## Environment variables
`MAPS_ENABLED` (default `false`), `MAPS_ROUTING_URL`, `MAPS_SEARCH_URL` (both HTTPS), `MAPS_API_KEY` (optional, secret),
`MAPS_TIMEOUT_SECONDS` (15), `MAPS_MAX_RESPONSE_BYTES` (524288). Enabling needs both URLs; it cannot be combined with
`RIDES_SYNTHETIC_ROUTING_ENABLED` or `DELIVERY_SYNTHETIC_ROUTING_ENABLED`.

## Verification
- Backend: contract tests over real HTTP replaying DEV responses (`KundeMapsRideRoutingTest`), `RideQuoteMapsIntegrationTest`
  (PostgreSQL, full Rides stack), `KUNDE_MAPS_LIVE=true ./gradlew test --tests '*KundeMapsLiveTest'` against the real DEV platform.
- Flutter: widget tests with the real SDK services over captured DEV responses (`test/features/rides/rides_maps_test.dart`,
  `delivery/delivery_maps_test.dart`, `executor/driver_navigation_test.dart`); the native map is replaced only in widget tests.
- Android emulator, nothing mocked: `scripts/ci/maps_native_e2e.py` (workflow "Taxi with KUNDE Maps Android E2E").

## Known limits
DEV Maps instances are free-tier and cold-start slowly; no reverse geocoder (a dropped pin is labelled by coordinates); no traffic;
Delivery consumer tracking is polling; the SDK is pinned by tag, so a Maps Platform API change needs an SDK release.
