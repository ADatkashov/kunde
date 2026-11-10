# 24 — Integration Architecture

All integrations sit behind capability interfaces and are selected only after functional, security, legal, regional and commercial review. A provider's API success is not equivalent to KUNDE business completion.

| Capability | Adapter contract | Operational controls |
|---|---|---|
| OTP/identity delivery | issue/verify challenge; delivery status where supported | Rate limits, generic responses, no code logs, provider fallback decision |
| Payment | attempt, authorize/capture if supported, query, void/refund, verified callback | Signature, idempotency, amount/currency validation, reconciliation, outage playbook |
| Maps/geospatial | geocode, route/estimate, optional map tile | Data minimization, manual fallback, region/coverage and caching terms |
| Partner catalog/fulfillment | catalog/availability/quote and accept/reject/status | Schema version, timeout, callback auth, inventory drift, human contact path |
| Dispatch/provider | eligibility/assignment/status/incident | Assignment expiry, minimal data, replay protection, reconciliation |
| Notifications | push/email/SMS/in-app channel send and receipt | Consent, dedupe, retry, DLQ, durable in-app status |
| AI model | typed text/tool result, usage/cost, safety metadata | Data processing terms/region, redaction, model allowlist, quota/fallback |
| Analytics | versioned event ingest and aggregate query | PII minimization, residency, retention, access and deletion review |

## Adapter requirements

Keep domain identifiers and statuses provider-neutral. Map provider error classes to KUNDE stable codes; persist external reference and normalized raw evidence under restricted access. Separate sandbox and production credentials. Webhooks require authenticated signature/mTLS or equivalent, freshness/replay checks, dedupe, schema validation and safe acknowledgment. Contract tests run against sandbox or provider simulator; no production call in CI.

## Readiness inventory

Unknown: selected payment rail/acquirer, OTP channel, maps/geocoder, delivery/dispatch partner, push/SMS/email providers, model provider, search engine, analytics platform, cloud region and partner APIs. For every procurement: confirm Kazakhstan personal-data region, subprocessors, cross-border support/telemetry, retention, incident SLA, export/exit, idempotency/webhook semantics, uptime and cost. Availability is not assumed.
