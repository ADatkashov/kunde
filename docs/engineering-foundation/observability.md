# Observability

Implemented: safe correlation-ID filter and response header, MDC context, structured console logging, generic API failures, Actuator health/liveness/readiness and graceful shutdown. Readiness includes PostgreSQL; liveness avoids external dependencies. Health detail is hidden.

Not configured: metrics exporter/backend, OpenTelemetry exporter, dashboards, alert delivery, mobile crash reporting, audit-event store, incident rota or approved SLOs. Prometheus is not exposed because no registry dependency is installed. Before pilot set D-12 objectives and alert owners for DB failure, API latency/errors, payment state (when implemented), migration and support incidents. Never include PII, tokens, addresses, prompts or financial payloads in telemetry.
