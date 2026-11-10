# 29 — Service Extraction Roadmap

## Keep modular for now

Identity/user, partner/catalog, pricing, orders, bookings, finance/payment coordination, support and AI remain in one deployable backend initially, with separate schema ownership and module contracts. This avoids distributed transactions and on-call burden while product workflow and team boundaries are still forming.

## Candidate order and triggers

| Candidate | Trigger evidence | Extraction prerequisites |
|---|---|---|
| Notifications | Fanout/retry load affects core worker; separate delivery SLO/team/vendor complexity | Versioned event contract, outbox consumer, recipient policy API, dedupe/inbox |
| Search projection | Search CPU/indexing competes with transaction DB or ranking cadence requires independent deploy | Rebuildable catalog feed, consistency/freshness SLO, backfill/replay, nonauthoritative index |
| AI orchestration | Model latency/cost/scale/security changes need independent resource limits or provider release cadence | Narrow tool API, permission/confirmation engine externalized as shared policy API, no direct DB, audit/cost pipeline |
| Payment adapter/reconciliation | Finance access isolation, provider complexity, volume/on-call justify separate deploy | Immutable ledger owner, signed callbacks, idempotency, reconciliation and incident drills |
| Dispatch/location stream | High-frequency location events/route latency exceed core DB/service budgets | Assignment contracts, data-minimization, region and retention controls |
| Analytics | Workload/reporting impacts OLTP or specialist data team appears | Minimized event schema, consent/retention, separate region/access approvals |

## Extraction sequence

1. Enforce module compile-time boundaries and own schemas.
2. Introduce stable command/query/event contract while still in-process.
3. Ensure outbox/inbox, idempotency, metrics, retries, DLQ and contract tests.
4. Move data ownership and deployable behind adapter; one writer at cutover.
5. Shadow-read/reconcile; migrate traffic gradually; define rollback and data ownership.
6. Retire old code only after evidence and audit.

Extract only for independent scaling, team ownership, security/regulatory boundary or reliability isolation—not for architecture aesthetics. Avoid shared DB writes after extraction.
