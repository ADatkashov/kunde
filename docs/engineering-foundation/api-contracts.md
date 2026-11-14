# API Contracts

Current OpenAPI 3.1 contract: `backend/src/main/resources/openapi/kunde-api-v1.yaml`. Base path remains `/api/v1`.

| Endpoint | Access | Behavior |
|---|---|---|
| `GET /api/v1/health` | Public | Process health; not dependency readiness |
| `GET /api/v1/capabilities` | Public | Release stage and capability booleans; no provider IDs or secrets |
| `GET /api/v1/categories` | Public | Published categories only (DRAFT/RETIRED hidden); empty until a catalog is published |
| `GET /api/v1/search?q=` | Public | Baseline name match over published categories (ranked exact/prefix/substring); blank `q` or no published catalog returns empty |
| `GET /api/v1/search/offerings?q=&limit=&offset=` | Public | Name match over PUBLISHED offerings in PUBLISHED categories, ranked exact/prefix/substring; `limit`<=100; only offerings of APPROVED partners (response carries `partnerId`, `partnerName`); no price or availability; blank `q` or unpublished catalog returns empty |
| `GET /actuator/health/readiness` | Public | Dependency readiness; details hidden |
| `POST /api/v1/me/support/cases` | Consumer JWT, `app.identity.consumer-enabled` | Opens an owner-scoped support case (`category` GENERAL/ACCOUNT/PRIVACY/APP_PROBLEM, `message` 1–2000). Requires `Idempotency-Key` (16–64 chars): 201 new, 200 replay, 409 `IDEMPOTENCY_KEY_REUSED` if the payload differs, 409 `CASE_LIMIT_REACHED` above 10 cases (technical guard). No transaction link yet |
| `GET /api/v1/me/support/cases[/{id}]` | Consumer JWT | Own cases only (`limit`<=100, `offset`); another user's case is `404 CASE_NOT_FOUND` |
| `POST /api/v1/me/support/cases/{id}/escalation` | Consumer JWT | Records the consumer's escalation request once (idempotent); promises no response time, queue or owner |

Errors have `timestamp`, numeric `status`, stable `code`, safe `message`, request `path` and `correlationId`. Responses include `X-Correlation-ID`; unsafe inbound values are replaced. With OIDC configured protected routes require a valid JWT; without an issuer they are denied. Client mutation models and auth endpoints are intentionally absent.
