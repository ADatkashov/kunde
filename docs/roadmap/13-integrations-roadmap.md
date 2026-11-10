# 13 — Integrations Roadmap

No provider is selected by this roadmap. Evaluate availability in Kazakhstan, service terms, support, price, data location, security, event semantics, sandbox quality and fallback before procurement.

| Capability | Need / priority | Dependencies and fallback |
|---|---|---|
| OTP/identity | Desired for MVP; provider/fallback unselected | D-05/D-07; development fake; production gate requires deliverability and abuse controls |
| Payments | Required only for real paid pilot | D-03/D-04/legal; contract-tested adapter; no real transactions if unavailable |
| Maps/geocoding | Serviceability/address support | D-11 and privacy/residency; manual address/service-area fallback only if operationally safe |
| Dispatch/last mile | Conditional on D-02 | Contracted partner events/API; merchant pickup/manual status only if truthful and staffed |
| Messaging/push | Transaction status and support | D-11, consent; in-app activity fallback, never rely on push as sole record |
| AI/model | Optional discovery assistance, later action preparation | D-08, evaluation/cost; deterministic search/help fallback |
| Analytics/monitoring | Operations and product signals | D-08/D-12; minimized first-party events and self-hostable/export option |
| Hosting/object storage | Production compute/data | Procurement/security/legal residency review; portable containers and backups |

Each adapter must define authentication, timeout/retry/idempotency, signature validation, event freshness/order, reconciliation, redaction, sandbox cases, cost owner, lock-in and exit plan. Avoid abstraction for a provider with no plausible replacement; abstract external money/identity/dispatch boundaries where substitution is realistic and required. Production credentials and personal data stay out of development/test environments.

