# 04 — Product Roadmap

Stages are sequential gates, not dated commitments. Exact scope is recorded in [`backlog/releases.yaml`](backlog/releases.yaml).

| Release | Goal and scope | Gate / key risk |
|---|---|---|
| Foundation | Decisions, product/API contracts, environments, identity/security, data/migrations, observability, design foundations and test automation | Architecture and privacy review; no unsupported vendor or cloud choice |
| MVP | One selected category, one limited zone, consumer discovery/order, partner operations, approved payment/fulfillment path, support/admin | D-01–D-08 resolved as applicable; signed cohort; E2E recovery and reconciliation rehearsal |
| Initial production launch | Invited/limited then public service in proven zone and hours | Supply, support, finance, legal, security, monitoring, rollback and pause thresholds all ready |
| Marketplace expansion | Improve catalog/search, partner tools, quality and add next category only after stable unit/ops evidence | Partner density, service quality and economics; category-specific policy |
| Everyday services | Add booking/home/mobility flows only where partner/provider operations support them | Booking/dispatch lifecycle and liability clear; provider tooling if required |
| Lifestyle | Events, family or other lifestyle capabilities only after specialist review | Child/health data and ticketing rules, consent and refund model |
| AI expansion | Grounded discovery/recommendations, then prepare actions with explicit confirmation | Evaluation, cost, privacy, freshness and safe tool authorization |
| Kazakhstan expansion | Add cities one at a time with localized supply, support, service areas and legal review | City readiness evidence and support coverage |
| International expansion | Country-specific product, payments, languages, data and operations | Local legal/tax/payment/security readiness; separate go/no-go |

For every stage: backend scope maps to domain modules and adapter contracts; mobile scope maps to design and API contracts; web scope is limited to partner/admin tools justified by operations; infrastructure is environment promotion and observability. No calendar estimate is approved because team capacity and vendor lead times are unknown.

