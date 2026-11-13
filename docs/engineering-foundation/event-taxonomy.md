# Event taxonomy and minimization (TASK-041)

Source of truth for event meaning: [PRD 1.1 §19](../product/PRD-1.1/19-analytics-and-events.md).
Code contract: `backend/src/main/java/kz/kunde/analytics/EventCatalog.java`, tested by `EventCatalogTest`.

## What exists

- A closed catalog of the 27 PRD §19 events, each with required/optional domain properties and an
  access class (`GENERAL` or `RESTRICTED`; payment, order, booking, cancellation, refund, support and
  AI task events are `RESTRICTED`).
- `EventCatalog.validate(name, properties)` returns every violation: unknown event, missing or
  extra property, envelope fields passed as properties, forbidden property names (matched by
  snake_case token: query, text, note, message, prompt, phone, email, address, lat/lon/geo,
  location, name, password, otp, token, card, pan, cvv, iban, health, child, birth), free-text or
  over-64-character string values, and non-scalar values.

## What does not exist (still gated)

No event is emitted, stored, queued or sent anywhere; there is no ingestion endpoint, vendor SDK,
mobile instrumentation or dashboard. Emission needs, at least: approved analytics consent and
policy text (TASK-007), residency/processor decisions (privacy-and-compliance.md), retention and
access policy per dataset, durable outbox with loss reconciliation (PRD §19 governance), and
approved KPI definitions (D-08/D-12, `docs/business/22-business-kpis.md`). TASK-042 dashboards
depend on this task and stay not started.

## Rules

- Envelope fields (`event_id`, `event_name`, `occurred_at`, `schema_version`, `actor_id`,
  `session_id`, `correlation_id`, `locale`, `app_version`, `market`) are added by the emitter, never
  by callers. `actor_id` must be pseudonymous and only where justified.
- No raw search text, address, phone, e-mail, precise location, health/child data, payment
  credentials, prompts or conversation content in any event. Use codes, bands and IDs.
- Adding an event or property is a reviewed change to `EventCatalog` plus its test; the catalog is
  not user-extensible at runtime.
