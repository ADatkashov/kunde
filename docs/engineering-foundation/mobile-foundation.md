# Mobile Foundation

The Flutter home foundation queries `/api/v1/capabilities`, displays server connection state and reports that marketplace, sign-in and AI are unavailable. Failed requests show a localized retry state; server response details are not rendered. API URL is a compile-time define and contains no secret.

Theme values use proposal tokens: primary `#0B6B5E`, canvas `#F6F7F4`, white surface and specified type sizes. Localization scaffolding supports RU/KK/EN; PRD D-15 still decides public languages and translation approval. Loading, offline, server-error and unavailable-capability states are represented. No token storage, nonfunctional navigation, catalog UI or crash-reporting SDK is included.

Further mobile work depends on approved screen flows, API contracts and identity decisions. Catalog UI must wait for server-backed data and category readiness.
