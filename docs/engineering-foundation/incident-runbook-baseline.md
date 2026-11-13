# Incident runbook baseline (TASK-048, draft)

Scope: only signals that exist in `main` today. There is **no** metrics exporter, dashboard, alert
delivery, on-call rota, approved SLO (D-12) or named owner (TASK-001); this file does not create them.
It is a starting point for the on-call owner once assigned, not an approved runbook.

## Signals available

| Signal | Where | Meaning |
|---|---|---|
| `GET /actuator/health/liveness` | Actuator, no detail | Process is up; no external dependencies checked. |
| `GET /actuator/health/readiness` | Actuator, no detail | Readiness state and PostgreSQL (`readinessState,db`). |
| `X-Correlation-ID` response header and `correlationId` in error bodies | `RequestCorrelationFilter` | Ties a user report to log lines. |
| One structured JSON log line per unhandled failure | console log | `correlationId`, exception type only; no message, stack or secrets. |

## Playbooks

**Readiness fails (503), liveness passes.** Most likely PostgreSQL is unreachable or refusing
connections. Check database availability and credentials/connection limits, then confirm readiness
returns to UP. Do not restart the app as the first step: liveness is healthy and a restart does not
fix the database. Traffic should stay off the instance while readiness is DOWN.

**Liveness fails.** The process is unhealthy: restart the instance, then check logs for the failure
that preceded it. Graceful shutdown waits up to 20 s.

**User reports an error.** Ask for the `correlationId` (shown in the error body/header), find the
matching JSON log line, and read the exception type. Never ask for or paste tokens, addresses or
personal data into tickets; telemetry must stay free of them.

**429 / rate-limit spikes.** Bounded request quotas are enforced before controllers (TASK-046). A
spike is a signal to investigate abuse or a misbehaving client; limits are configured by
`API_AUTH_RATE_LIMIT_*` and must not be raised to silence it without review.

## Not covered (open)

Alert thresholds and owners, escalation and on-call, SLO-based paging, dashboards, payment/migration/
support incident playbooks (those features do not exist yet), audit evidence, post-incident review
template, mobile crash reporting. See [observability](observability.md).
