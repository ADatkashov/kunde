# 17 — Testing Strategy & QA Roadmap

Testing requirements are planned gates; they have not been executed by preparing this roadmap.

| Layer | Required evidence |
|---|---|
| Unit | Domain rules, prices/eligibility, state transitions, validation and authorization decisions |
| Integration/database | Repositories, constraints, migration compatibility, transactions, outbox and rollback |
| API/contract | OpenAPI compatibility, auth scopes, idempotency, error shape and provider contracts |
| Mobile/component/widget | Design system states, validation, accessibility semantics, localization, session/error/offline handling |
| End-to-end | Browse → quote → order → partner/fulfillment → payment result → activity/support; include rejects, timeout, duplicate, cancel/refund |
| Performance/reliability | Approved D-12 workload/SLO, dependency timeout, queue backlog, restart and restore/reconciliation behavior |
| Security/privacy | Abuse/rate limits, access-control negatives, secret/PII leak checks, webhook replay and data deletion/retention controls |
| Accessibility/localization | Critical journeys, screen reader/contrast/input, Kazakh/Russian approved copy and currency/date formats |
| AI (when enabled) | Versioned eval sets for freshness, grounding, prompt/tool abuse, refusal, confirmation integrity, latency and cost |

## Quality gates

- PR: formatting/static analysis, relevant unit/component tests, contract checks, review, no secret/high-confidence critical scanner finding.
- Merge: required checks green, migration reviewed and backward-compatible, feature flag/default behavior reviewed.
- Release candidate: regression suite, E2E and provider sandbox scenarios, accessibility/localization, security and observability evidence, operational checklist.
- Production: signed approval for legal/finance/operations/security gates; staged cohort, dashboards/alerts and tested pause/rollback; unresolved critical defect or unowned alert means No-Go.

Every epic maps minimum tests to its feature risk. Payment, identity, order state, admin and privacy changes require negative/failure-path tests, not happy path only.

