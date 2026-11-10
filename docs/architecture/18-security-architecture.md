# 18 — Security Architecture and Threat Model

## Identity/session

Recommend standards-based OIDC-compatible identity service or managed identity only after Kazakhstan region, data handling and vendor review. Short-lived access tokens; refresh-token rotation/reuse detection; revoke by device; secure mobile storage; no credentials in logs. MFA/step-up for staff, finance, payout and privileged actions. OTP is a verification channel, not sufficient high assurance for admin.

## Authorization and isolation

RBAC grants coarse action; ABAC scopes user, family/guardian, business/location, assigned task, case, data class and purpose. Deny by default at API/domain boundary. Tenant ID derives from validated grant, never trusted from body. Automated tests cover cross-tenant IDOR and revocation. Partner/provider roles do not inherit user data; admin access is case/purpose-scoped. AI inherits caller authority and cannot elevate it.

## Data protection

TLS in transit; managed KMS-backed encryption at rest; field-level encryption/tokenization for high-risk identifiers as needed. Secrets in vault/managed secret store, rotation, least access. Payment card data stays in provider-hosted/tokenized flow; do not store PAN/CVV. Sensitive children/health/exact location separated, minimized, encrypted, audited and retained only under approved policy. Backups, logs, support exports and analytics follow same classification.

## Threats and controls

| Threat | Example | Control |
|---|---|---|
| Account takeover | OTP brute force, SIM swap, stolen refresh token | Rate/device limits, challenge expiry, anomaly detection, revoke sessions, step-up and recovery policy |
| Broken access control / IDOR | Partner changes another order by guessing ID | Resource-level authorization on every call, tenant-scoped queries, negative contract tests |
| Replay/duplicate charge | Retry after timeout or replay webhook | Idempotency, signed timestamped webhook, provider event dedupe, reconciliation |
| Booking race | Two users claim last appointment | Atomic hold/unique resource constraint, expiry and concurrency tests |
| Insider misuse | Support bulk views customer profiles | Case-bound access, masking, audit/alerts, separation, access review |
| Supply fraud | Fake business/provider or altered catalog | Verification, moderation, anomaly/fraud signals, suspension workflow |
| Mobile compromise | Reverse-engineered client secrets | No embedded secrets; server enforcement; root/jailbreak signals as risk input, not sole control |
| Prompt injection/tool abuse | Listing text asks agent to leak data | Treat content as untrusted; allowlisted tools, typed args, scoped retrieval and confirmation |
| Data exfiltration | Overbroad analytics/logging/export | Data classification, redaction, role separation, retention and DLP review |
| Denial/abuse | Search/OTP/order floods | Per-IP/account/device limits, quotas, bot signals, cost budgets and graceful degradation |

Threat model follows OWASP Mobile, API Security and Top 10 guidance; run threat modeling and independent testing before pilot. Monitor payment anomalies, unusual access, role changes, AI tool denials and provider webhook signature failures. Incident response includes containment, credential rotation, evidence preservation and user/regulator notification obligations reviewed by counsel.

## Kazakhstan and other markets

Design primary personal-data storage/processing in Kazakhstan for initial market, subject to current legal interpretation. Official Kazakhstan rules state storage in databases located in Kazakhstan and require review for cross-border transfer/third-party processing; use local counsel to validate exact scope, exceptions and current amendments: [Personal Data Law](https://old.adilet.zan.kz/eng/docs/Z1300000094), [collection/processing rules](https://old.adilet.zan.kz/eng/docs/V2000021498). No customer PII to a foreign AI, analytics, maps or support service until counsel, consent/basis, contracts and data-flow review approve. Multi-country later requires separate country-specific assessment.
