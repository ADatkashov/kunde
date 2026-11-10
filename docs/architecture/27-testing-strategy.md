# 27 — Testing Strategy

Testing is layered around domain invariants and recoverability, not only endpoint happy paths.

| Level | Scope and critical checks |
|---|---|
| Unit | State transition guards, quote math, policy versioning, permission evaluation, idempotency-key behavior, AI confirmation binding |
| Module integration | PostgreSQL constraints/migrations, outbox atomicity, slot contention, immutable ledger, tenant scoping |
| API/contract | OpenAPI compatibility, error envelope, auth scopes, pagination, provider webhook signature/dedupe, partner contract adapters |
| End-to-end | Consumer registration→search→order/booking→activity/support; partner accept/reject; provider status; admin scoped resolution |
| Mobile | iOS/Android supported OS, localization, accessibility, offline state, deep links, secure session storage, crash recovery |
| Payment | Sandbox/simulator plus deterministic fault injection: timeout, delayed success, duplicate webhook, partial refund, order-persistence outage, provider mismatch |
| Performance | Search, checkout, concurrent last-slot hold, callback bursts, queue lag and DB pool saturation against agreed workload |
| Security | Threat model, SAST/DAST/dependency/container scans, mobile/API penetration, IDOR/tenant isolation, abuse/rate limits, secrets |
| AI evaluation | Tool allowlist, prompt injection, permission leakage, ambiguous request, stale quote/slot, altered draft, partial failure, refusal and cost caps |
| Resilience | Provider outage, retry storm control, queue poison event, DB restore, region failover fencing and replay |

## Required transaction scenarios

Test “payment confirmed but order persistence fails”, “merchant rejects after authorization”, “payment webhook arrives twice/out of order”, “refund provider is pending/fails”, “slot lost before confirmation”, “reschedule fails while old slot remains”, “worker update after assignment revocation”, and “AI confirmation draft version changed”. Assert no duplicate financial effect and truthful customer status.

## Test data and release gate

Use synthetic/fabricated identities and provider simulators; do not clone production PII. Every PRD requirement ID must link to acceptance tests when implementation begins. Critical/high security and payment integrity defects block release. Chaos testing is limited to staging and planned failure drills; not required in early dev.
