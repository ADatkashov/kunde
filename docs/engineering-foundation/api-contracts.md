# API Contracts

Current OpenAPI 3.1 contract: `backend/src/main/resources/openapi/kunde-api-v1.yaml`. Base path remains `/api/v1`.

| Endpoint | Access | Behavior |
|---|---|---|
| `GET /api/v1/health` | Public | Process health; not dependency readiness |
| `GET /api/v1/capabilities` | Public | Release stage and capability booleans; no provider IDs or secrets |
| `GET /api/v1/categories` | Public | Empty until approved persistent catalog exists |
| `GET /api/v1/search?q=` | Public | Empty until approved catalog/search exists |
| `GET /actuator/health/readiness` | Public | Dependency readiness; details hidden |

Errors have `timestamp`, numeric `status`, stable `code`, safe `message`, request `path` and `correlationId`. Responses include `X-Correlation-ID`; unsafe inbound values are replaced. With OIDC configured protected routes require a valid JWT; without an issuer they are denied. Client mutation models and auth endpoints are intentionally absent.
