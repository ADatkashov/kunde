# 22 — Non-Functional Acceptance Criteria

Targets below are proposed for architecture validation, not approved SLOs. Security, privacy and data integrity criteria are required before public transactions.

| ID | Area / proposed acceptance | Target status |
|---|---|---|
| NFR-SEC-001 | All network traffic uses modern TLS; secrets are managed outside source/config; sensitive stored data is encrypted at rest with access-controlled key rotation. | Mandatory control; implementation architecture TBD |
| NFR-SEC-002 | Authorization is server-enforced, deny-by-default, least privilege; privileged/financial actions require step-up auth and immutable audit. | Mandatory |
| NFR-SEC-003 | Threat modeling and security review cover auth, payment, role boundaries, APIs, AI tools and abuse before pilot; critical/high findings block launch. | Proposed launch gate |
| NFR-PRIV-001 | Data inventory, purpose, consent, retention, deletion and access control are documented; sensitive child/health/precise location fields are minimized. | Mandatory; legal review TBD |
| NFR-DATA-001 | Payment and transaction event processing is idempotent; duplicate webhook/retry tests produce one financial effect; immutable journal reconciles to provider. | Mandatory |
| NFR-REL-001 | Proposed consumer API availability ≥99.5% monthly for pilot, excluding declared maintenance; validate against operating model. | Proposed target |
| NFR-REL-002 | Failed/ambiguous payment and order handoff is detectable, recoverable, and has an on-call/operations owner; backup restore is demonstrated before launch. | Mandatory gate |
| NFR-PERF-001 | Proposed p95 API response ≤500 ms for read APIs and ≤1 s for non-provider mutation work, excluding external-provider wait; validate with workload and device tests. | Proposed target |
| NFR-PERF-002 | Search first result response proposed ≤1.5 s p95 in launch region under agreed load; mark target pending benchmark. | Proposed target |
| NFR-OBS-001 | Every transaction carries correlation IDs through app/API/provider events; dashboards and alerts cover error rate, unknown payments, orphan orders, refund age, partner timeouts and dispatch failures. | Mandatory |
| NFR-OBS-002 | Logs avoid secrets and unnecessary personal data; access and retention are reviewed; errors are actionable and paged by severity. | Mandatory |
| NFR-A11Y-001 | Core flows support screen readers, focus order, semantic controls, dynamic text and sufficient contrast; test on supported platforms. | Mandatory |
| NFR-I18N-001 | Kazakh and Russian critical flows have reviewed strings and correct date/number/currency/time display; English resources supported architecturally. | Mandatory for launch |
| NFR-SCALE-001 | Workload tests validate expected launch peak and forecast; horizontal scale and integration isolation are demonstrated where architecture requires. | Target pending estimation |
| NFR-DR-001 | Proposed RPO ≤15 min and RTO ≤4 h for transaction data, subject to architecture/cost/legal validation; backup restore runbook tested. | Proposed target |
| NFR-CLIENT-001 | Core browse screens provide clear network/empty/error states; checkout and other consequential actions require online server revalidation. | Mandatory |

Performance values must be revised after traffic assumptions, region, vendor latency and cost are known. A target without an instrumented measurement and owner is not a launch criterion.
