# 16 — Roles and Responsibilities

RACI key: **R** performs, **A** accountable, **C** consulted, **I** informed. One accountable owner per row; roles are organizational responsibilities, not automatic system permissions. System authorization remains scoped per PRD 1.1 §13.

| Operation | Customer | Partner owner/manager | Partner employee | Driver/provider | Support | Operations | Finance | Moderator/Compliance | Admin | Payment provider |
|---|---|---|---|---|---|---|---|---|---|---|
| Accurate customer request/consent | A/R | I | I | I | C | I | I | I | I | C |
| Business onboarding and catalog | I | A/R | R (grant) | — | C | C | C | C | I | I |
| Accept/prepare merchant order | I | A | R | R if assigned | I | C | I | I | I | I |
| Deliver/perform task | I | A/C by contract | I | R | I | A for platform lane | I | C safety | I | I |
| Customer support case | C | C | I | C | A/R | C | C money issue | C safety/legal | I | C provider case |
| Refund request/recommendation | R request | C evidence | I | C evidence | R case | C | A/R financial action | C legal | I | R execution/confirmation |
| Payment capture/settlement/reconcile | I | I | I | I | I | C | A/R | C | I | R rail execution |
| Content/review moderation | C/report | C reply | I | C reply | I | C | I | A/R | I | — |
| Provider verification/eligibility | I | C | — | R submit | I | A/R operational | C payout | C legal/trust | I | C identity/bank provider |
| Market/category activation | I | C | I | C | C | R | C | C | A | C |
| AI tool execution | A consent | I | — | I | C | C | I | C policy | I | I |

## Party boundaries

- **Customer:** accurate instructions, authorized beneficiary/location, review exact terms, report issue; never responsible for platform/provider integrity failures.
- **Partner:** lawful supply, truthful listing/price/availability, accepted fulfillment, staff access, category obligations and evidence.
- **Provider:** eligibility and safe, timely completion of assigned scope; no unapproved extra charges.
- **KUNDE platform:** marketplace controls, transaction/status coordination, data protection, support routing, monitoring, policy enforcement and accurate disclosure under executed model.
- **Payment provider:** licensed payment execution/status/settlement services within its contract; it does not decide product fulfillment.

## Separation of duties

Support does not silently alter ledger; Moderator cannot issue refund by default; Finance cannot read unrelated family/health messages; Admin role does not imply unrestricted PII access; super-admin break-glass is time-bound and reviewed. Bank beneficiary change, manual high-value refund and contract exception require maker/checker policy (threshold TBD).
