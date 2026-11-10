# 18 — Team & Ownership Model

No role or headcount is assumed to exist. Assign named accountable owners before each gate.

| Role | Ownership |
|---|---|
| Product manager | Outcome, scope, decisions, priority and acceptance |
| Product/UX designer | Research, flows, design system, accessibility and localized states |
| Backend engineer/lead | Domain contracts, data correctness, API and backend quality |
| Flutter engineer | Consumer app, client integration and platform behavior |
| Web engineer | Partner/admin web surfaces if selected for pilot |
| QA engineer | Risk-based test design, automation and release evidence |
| DevOps/SRE | Environments, deployment, telemetry, backups, on-call and recovery |
| Security/privacy | Threat model, access, secure delivery, privacy and risk sign-off |
| Data/analytics | Event definitions, data minimization and reliable metrics |
| AI engineer | Optional model gateway, evaluations and safe tool integration |
| Business operations | Supply, fulfillment, support, incidents and readiness |
| Finance/legal/trust | Funds flow, terms, reconciliation, compliance and approval controls |

Minimum viable cross-functional ownership: product + design, backend, Flutter, QA, operations, finance/legal input and shared DevOps/security. This describes capabilities, not a guaranteed small team size. Code owners review domain and security-sensitive changes; payment/refund and authorization changes need independent reviewer approval. Product, legal/finance and operations own decisions engineers cannot infer.

