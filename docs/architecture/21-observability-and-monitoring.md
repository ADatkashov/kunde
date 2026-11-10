# 21 — Observability and Monitoring

## Telemetry

- Structured logs: timestamp, severity, service/module, environment, correlation/trace ID, actor pseudonym if justified, outcome/error code; redact phone, address, prompt, token, card data and child/health fields.
- Metrics: RED for APIs (rate/errors/duration); DB pool/lock/replication; worker queue lag/retries/DLQ; provider latency/error; mobile crash/startup; business conversion and fulfillment outcomes.
- Traces: OpenTelemetry-compatible context across API, outbox, worker and provider adapter; do not add PII as span attributes.
- Audit stream is distinct, append-only and access-restricted; general logs are not a substitute.

## Proposed SLI/SLO candidates

| SLI | Proposed pilot objective | Notes |
|---|---|---|
| API availability | 99.5% monthly for critical read/command routes | Validate budget/maintenance and regional vendor dependency |
| Search p95 | ≤1.5 s for first page | External geo excluded or separately reported |
| Core API p95 | ≤500 ms read, ≤1 s internal command processing | Provider wait measured separately |
| Payment state reconciliation | 99% of known provider events applied within 2 min | Vendor callback/query capability and business hours affect target |
| Outbox delivery | 99% nonfinancial messages under 1 min; financial exceptions alerted immediately | Do not equate notification delivery with transaction success |
| Booking conflict | Zero confirmed double bookings in concurrency test | Integrity property, not percentile |

All values are proposed, not approved contractual SLOs. Set error budgets, paging policy and owners after workload/vendor tests. Alert on unknown payment age, orphan paid transactions, refund aging, booking hold expiry failures, partner timeout, webhook signature errors and authorization anomalies. AI monitor task completion, tool-denial rate, p95 latency, token/cost, fallback and user correction; never optimize cost by weakening confirmation.
