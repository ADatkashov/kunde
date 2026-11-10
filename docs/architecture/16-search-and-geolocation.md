# 16 — Search and Geolocation Architecture

## Geo sources

User-provided/saved address is primary fulfillment input. Device location is optional and permission-gated. Geocoder/map service is an adapter that suggests/normalizes addresses and may provide route estimates; its output is not a legal address or final serviceability decision. KUNDE owns service-area eligibility configuration and provider capability metadata.

## Search pipeline

Catalog publication → outbox `CatalogPublished` → projection worker → PostgreSQL full-text search initially, then optional OpenSearch. Search returns grouped type/category results, location/filter/ranking metadata and `updatedAt`; checkout fetches canonical catalog/quote to revalidate. Search projection is disposable and rebuildable; it cannot authorize order/booking.

## Privacy and precision

Use selected address ID/service area when possible; send exact coordinates to external route/geocoder only when necessary, consented and contractually approved. Store separate display address, normalized reference and protected coordinates. Provider receives only assignment-required pickup/dropoff and limited duration. Logs/analytics use coarse region, not exact coordinates.

## Provider abstraction and failure

Geocoding, routing, map tiles and reverse geocoding are separate capability interfaces. Record source, precision, freshness and confidence. If external map is unavailable, manual address and configured polygon/service area remain; disable fare/ETA promise when route cannot be calculated. The app must not display fake live tracking.

## International readiness

Service areas, language variants, address parsers, units, local time zones and currency are region configuration. Use PostGIS geometry with SRID and explicit data-region ownership. Evaluate residency for coordinates/address and map vendor processing before enabling market. Do not assume a map provider or Kazakhstan coverage.
