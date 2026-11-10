# 20 — Integration Requirements

Functional contracts only; provider choice and capability are open. Adapters isolate external vendors so KUNDE domain state remains authoritative and portable.

| Integration | Required contract | Failure/security behavior |
|---|---|---|
| SMS/OTP | Request, deliver, verify challenge; expiry/throttle result; provider abstraction | Never log code; rate limit; delivery failure recoverable; no account enumeration |
| Payment | Create attempt, authorize/capture where supported, query status, void/refund, webhook verification, reconciliation export | Signed/authenticated events, dedupe, idempotency, amount/currency validation; unknown state stays pending |
| Maps/geocoding | Address suggestion/validation, service-area/route estimate only where vendor supports | Permission-minimized coordinates, manual entry fallback, no false live tracking claim |
| Partner catalog/fulfillment | Catalog, availability, quote, accept/reject, fulfillment events, cancellation | Versioned data, timeout policy, idempotent request IDs, stale catalog surfaced |
| Dispatch/driver | Eligible provider lookup/assignment, accept/reject, status and incident events | Assignment scopes, event authentication, reassignment and no-provider recovery |
| Push/email/messaging | Send transactional or consented marketing event, delivery outcome when available | Outbox, dedupe, retries, channel preference and in-app fallback |
| AI/model provider | Provider-neutral orchestration, structured tool calls, safety/usage metadata | Model output is untrusted; tool allowlist and user authorization enforced by platform |
| Analytics | Versioned event ingest and aggregate reporting | Minimize identifiers, buffer/retry without transaction blocking |

## API conventions (proposed)

- Base path `/api/v1`; JSON UTF-8; HTTPS in deployed environments; authenticate with short-lived token mechanism to be selected.
- Stable resource IDs, ISO timestamps, ISO currency, integer minor units, explicit locale/time zone where relevant.
- Mutating commands accept `Idempotency-Key`; updates use resource version/ETag to reject stale transitions.
- Standard error envelope: `code`, localized-safe `message`, `correlationId`, `retryable`, optional `currentVersion`; never leak provider secrets.
- Paginated list uses opaque cursor; list filtering is server-authorized.
- Webhooks authenticate signature/identity, dedupe event ID and preserve raw restricted evidence under retention policy.
- API never trusts client role, amount, payment success, quote or AI action arguments; revalidate server-side.

## Proposed endpoint surface

`/auth/challenges`, `/me`, `/me/addresses`, `/categories`, `/search`, `/businesses/{id}`, `/products`, `/services`, `/carts`, `/orders`, `/bookings`, `/payments`, `/support/cases`, `/notifications/preferences`, `/families`, `/assistant/conversations`, `/assistant/tasks`. Transaction action routes should be explicit commands (`accept`, `cancel`, `capture`, `refund`) rather than arbitrary status patch. Existing code currently implements only demonstration health/categories/search/assistant endpoints and is not yet compliant with these contracts.

## Integration readiness gate

For each chosen vendor, record capability evidence, sandbox/production distinction, timeout/retry limits, idempotency semantics, data residency, webhook security, reconciliation process, support escalation, cost, exit path and owner. Do not infer features from marketing material or assume a webhook is always timely.
