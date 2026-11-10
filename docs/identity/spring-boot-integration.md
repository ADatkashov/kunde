# Spring Boot integration specification

## Existing state and target

Current Spring Security/OIDC resource-server boundary validates JWT issuer and audience from configuration and fails closed when issuer is absent. Keep this behavior. There is no token issuer, account/session lifecycle or identity database integration. Do not add auth behavior or migrations in this design phase.

## Configuration contract

Per environment configure exactly one approved issuer, audience/resource IDs, approved signing algorithms, discovery/JWKS policy, allowed client IDs where relevant, clock skew, access policy and outbound TLS. Secrets (if service credentials are required) come from managed secret storage, never committed `application*.yml`, logs or mobile assets. Dev issuer must not be accepted in staging/prod. Reject startup or readiness when required production values are absent or malformed.

## Request validation

Validate signature and key, issuer exact match, API audience, `exp`, `nbf`, required client/authorized-party constraints and token type/policy. Do not decode-and-trust JWT claims without signature verification. Do not fetch arbitrary `jku`/`x5u`. Cache JWKS; refresh on unknown `kid` with rate limiting; tolerate overlap during rotation. On discovery/JWKS failure, cached valid keys can be used within bounded policy, but no validation rule is skipped.

## Principal mapping and authorization

Map `(iss,sub)` to canonical KUNDE ID through an identity service; fail closed for unmapped/deleted/suspended accounts. Spring authorities are coarse API permissions only. Domain services enforce membership and resource ownership. Public routes are explicitly allowlisted and narrow; all other routes require authentication. Avoid broad wildcard matcher ordering. Error responses avoid leaking account existence.

## Operations

Redact bearer headers, codes, phone and email from access logs/traces. Emit structured auth outcome categories and correlation IDs. Monitor unknown issuer/audience, signature failures, JWKS refresh, login/revocation failure, OTP spend/rate patterns and admin actions. Backoff on provider outages; do not silently accept unsigned/local tokens. Define revocation propagation SLO and known short-lived JWT window.

Service-to-service calls use a distinct client-credentials or workload identity with narrow audience/scopes and key rotation. They do not impersonate user tokens. Configure local integration tests against a test issuer later in implementation, without weakening production config.
