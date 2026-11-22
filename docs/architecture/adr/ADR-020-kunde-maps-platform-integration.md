# ADR-020 — KUNDE Maps Platform integration

- Status: Proposed — prepared at the owner's request (2026-11-22); implementation is flag-gated, internal environments only. Accepted only after owner review.
- Date: 2026-11-22
- Scope: map, address, routing and navigation capabilities of Consumer, Executor, Partner and the backend
- Companion: [kunde-maps ADR 0007](https://github.com/ADatkashov/kunde-maps/blob/main/docs/architecture/decisions/0007-kunde-maps-sdk-and-ecosystem-integration.md) (SDK architecture and audit of both repositories)
- Complements: ADR-019, existing Rides (V22/V23) and Delivery (V27/V28/V31) modules; modifies none of their ownership

## Context
Audit of `main` (code, not documentation): Rides and Delivery already depend on one provider seam, `RideRouting` (geocode, reverse geocode, road route),
but only `SyntheticRideRouting` implements it, so both products fail closed with 503 unless a fixture is enabled in an internal environment. No
Flutter app contains a map; Consumer shows address search results as a list and the driver position as numbers. The independent KUNDE Maps Platform
(`kunde-maps`) already runs Search/Places and Routing services on OpenStreetMap data.

## Decision
1. **Backend** — one adapter, `kz.kunde.maps.KundeMapsRideRouting`, implements the existing `RideRouting` seam over the Maps HTTP contracts
   (`POST /v1/routes`, `GET /v1/search`, `GET /v1/places`). It copies no routing engine, graph or map data. It is created only when
   `app.maps.enabled=true` with HTTPS URLs; it cannot be combined with the synthetic fixtures. Rides and Delivery then use real road distance
   and typical time, unchanged otherwise.
2. **Ownership stays where it is.** Rides owns quotes, tariff, trip state and payments; Delivery owns jobs, dispatch and tracking. Maps supplies
   distance, duration and geometry only. **A distance is not a fare**: the quote price is computed by the Rides/Delivery tariff from the Maps route,
   and the response says the time is typical (no traffic).
3. **Failure semantics.** "No match" answers from Maps (no road, out of coverage, points too close) are an empty result (HTTP 422 for quotes).
   Timeouts, quota, authentication, 5xx and malformed or oversized answers are `RideRouting.Unavailable` (HTTP 503, no fallback price). One retry for a
   warming-up service (502/503/timeout). Coordinates and queries are never logged or placed in exception messages. The API key (optional) is a secret.
4. **No reverse geocoder is faked.** Reverse lookup returns only a real nearby place that carries an address, otherwise "not found".
5. **Clients** consume the `kunde_maps_sdk` Flutter package from the kunde-maps repository (pinned git tag), behind backend flags; no map code is
   copied into this repository. Heavy navigation is used only by Executor/driver guidance; address selection uses the lightweight picker.
6. **Live tracking** keeps the existing rules (authorised owner/assignee, 5 s write limit, positions deleted when the job ends, 2-minute freshness) and
   adds none that weaken them; the Maps Platform never receives driver or courier identity, only coordinates needed for a route.
7. No new service. One adapter and configuration class in the modular monolith.

## Configuration
`MAPS_ENABLED` (default false), `MAPS_ROUTING_URL`, `MAPS_SEARCH_URL`, `MAPS_API_KEY` (optional), `MAPS_TIMEOUT_SECONDS` (15), `MAPS_MAX_RESPONSE_BYTES` (524288).
Rides remains limited to internal environments by `RidesConfiguration`; production enablement needs a separate owner decision and deployment approval.

## Verification
Contract tests replay responses captured from the deployed DEV Maps Platform over real HTTP; `RideQuoteMapsIntegrationTest` drives the full Rides stack
(security, tariff, PostgreSQL) through that adapter; `KundeMapsLiveTest` (`KUNDE_MAPS_LIVE=true`) calls the real DEV platform without mocks.

## Consequences and limits
Typical time without traffic; DEV Maps instances are free-tier and cold-start slowly (first request can take tens of seconds); no reverse geocoder yet;
production capacity and quotas of the Maps Platform are not sized.
