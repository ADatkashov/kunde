# 30 — Architecture Risks

| Risk | Likelihood / impact | Mitigation and decision owner |
|---|---|---|
| No suitable verified Kazakhstan region/service for chosen managed stack | Medium / critical | Procurement/legal data-flow audit before vendor selection; choose in-country deployment and minimize external PII |
| Payments/order handoff creates duplicate charge or orphan transaction | Medium / critical | Idempotency, verified state, outbox/saga, immutable journal, reconciliation and fault-injection tests; Finance/Engineering |
| Marketplace supply/fulfillment is not operationally ready | High / high | Gate each category; pilot cohort/operations runbook; Product/Operations |
| Modular boundaries degrade into shared database monolith | Medium / high | Schema ownership, module dependency rules, architecture tests, code owners; Engineering |
| Team lacks mobile/Flutter or Spring production expertise | Unknown / high | Skills/capacity assessment and prototype before commitment; CTO |
| Managed infrastructure chosen without acceptable KZ data location | Medium / critical | Verify primary, backup, logs, support and AI processing locations contractually; Legal/Security |
| Search index stale causes unavailable items/appointments | Medium / medium | Canonical revalidation at checkout/booking and freshness timestamp; Catalog/Search |
| Model output leaks data or triggers unintended tool action | Medium / critical | Permission-scoped tool gateway, no DB access, explicit confirmation, redaction, adversarial eval; AI/Security |
| Family/child/health data exposed across roles | Low-medium / critical | Separate scopes, guardian validation, sensitive data review and delayed category launch; Privacy/Legal |
| Vendor lock-in/payment/map/model integration limits market expansion | Medium / high | Capability adapters, export/exit tests, portable domain IDs and provider contract review; Architecture |
| Premature platform infrastructure increases cost/on-call | Medium / medium | Defer Kafka/K8s/search/cache until measured trigger; CTO/Operations |
| Unclear retention/deletion conflicts with financial audit | Medium / high | Data inventory and field-level retention/legal hold policy before launch; Legal/Finance |

Risk owners and acceptance dates are TBD; architecture approval should assign them. No vendor availability or team capacity is assumed.
