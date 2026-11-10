# 16 — AI Engineering Roadmap

AI is outside transactional MVP critical path. All versions use normal backend APIs, user permissions, business rules, data minimization, grounded outputs, measured cost and fallback behavior.

| Version | Capability and dependencies | Release gate |
|---|---|---|
| AI 1.0 | Conversational help, natural-language catalog search, basic recommendations; depends on stable search/catalog and approved model/data processor | Offline evaluation, privacy/vendor review, truthful availability and cost dashboards |
| AI 2.0 | Result comparison, context-aware and personalized recommendations | Consent, ranking quality/bias review, opt-out and measurable lift |
| AI 3.0 | Prepare order/booking, show exact items/price/time/policy preview, obtain explicit user confirmation | Server revalidates quote/availability/permission; cancel/edit path; confirmation bound to current preview |
| AI 4.0 | Multi-step orchestration via allowlisted tool registry, progress, recovery and retries | Tool-level auth, idempotency, bounded actions, audit, timeout/compensation and human escalation |
| AI 5.0 | Cross-category personal life assistant and proactive suggestions with consent | Per-purpose consent, controls, deletion, safety evaluation and country/category approvals |

Never allow model output to assert an order is placed without verified backend state, bypass authorization, write ledger state, invent availability/price, or take a consequential action without required user confirmation. Evaluate relevance, groundedness, refusal, tool misuse, latency, cost per successful session and fallback success. Use a provider-neutral gateway only where the substitution benefit exceeds operational complexity; D-08 governs data processors.

