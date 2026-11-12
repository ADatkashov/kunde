# Observability

Implemented: safe correlation-ID filter and response header, MDC context, structured console logging, generic API failures, Actuator health/liveness/readiness and graceful shutdown. Readiness includes PostgreSQL; liveness avoids external dependencies. Health detail is hidden.

Not configured: metrics exporter/backend, OpenTelemetry exporter, dashboards, alert delivery, mobile crash reporting, audit-event store, incident rota or approved SLOs. Prometheus is not exposed because no registry dependency is installed. Before pilot set D-12 objectives and alert owners for DB failure, API latency/errors, payment state (when implemented), migration and support incidents. Never include PII, tokens, addresses, prompts or financial payloads in telemetry.

## Verified telemetry boundary (TASK-047, 2026-11-12)

`TelemetryBoundaryIntegrationTest` and `RequestCorrelationFilterTest` verify against the
PostgreSQL-backed application context: every response class (200, 400, 404/denied, 503 protected,
CORS preflight 403) carries a generated `X-Correlation-ID` and error bodies repeat it; unsafe or
oversized caller IDs are replaced; MDC is cleared even when the chain fails; an unhandled failure
is logged as one structured JSON line with `correlationId`, exception type only, no message, no
stack trace and no request secrets; Actuator serves only `health` and its probes, without database
or component detail. Checked by mutation (health detail enabled, exception message logged).

Still open and **not** implemented or verified: named alert owners and on-call (blocked on TASK-001
owner assignment), approved SLOs (D-12), metrics/OpenTelemetry exporter, dashboards and incident
runbooks (TASK-048), alert delivery, audit-event store and mobile crash reporting.
