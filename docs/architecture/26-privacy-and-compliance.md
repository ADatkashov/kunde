# 26 — Privacy and Compliance Architecture

This document is not legal advice. Build a data inventory/processing register and conduct counsel/privacy review before production.

## Data classification and lifecycle

| Class | Examples | Controls |
|---|---|---|
| Public | Published catalog, public business description | Integrity/moderation, cache policy |
| Personal | Phone, profile, saved address, transaction references | Purpose and consent/legal basis, access/export/deletion workflow, in-country storage review |
| Sensitive/high impact | Precise location, child/dependent data, health, identity evidence, support attachments | Minimize, separate, encrypt, narrow roles, short retention, purpose audit, no general analytics/AI context |
| Financial/security | Payment references, ledger, auth/audit events | Immutable, restricted, segregated, reconciliation and incident audit |

## Kazakhstan residency/data flows

Official Kazakhstan sources state that personal data storage occurs in a database located in Kazakhstan and regulate cross-border transfer/third-party processing. Architecture recommendation: place authoritative KZ personal-data stores and backups in a verified in-country region and block foreign processors from receiving PII until legal review confirms a basis, consent and contractual protections. Relevant sources: [Law on Personal Data](https://old.adilet.zan.kz/eng/docs/Z1300000094) and [collection/processing rules](https://old.adilet.zan.kz/eng/docs/V2000021498). These instruments have amendments; counsel must verify current consolidated text, applicability, exceptions and future launch date. A cloud provider marketing a “region” is not proof every log, backup, support access or model request stays there.

## Required capabilities

- Purpose/consent records with version, locale, timestamp and withdrawal effects.
- Data subject access/export/delete workflow with legal hold/financial retention exception and status.
- Field-level classification, access policy and retention schedule; backups and logs included.
- Processor inventory, data-processing terms, subprocessors and region verification.
- DPIA/privacy impact assessment for health, children, precise location, AI profiling and cross-border processing where counsel requires.
- AI prompt/context filters; no raw payment credentials; no child/health content in general model request without explicit lawful/contractual approval.
- Breach and data-subject request incident runbooks.

## Expansion

Each country/market requires legal matrix, localization and local storage/transfer determination. Do not assume KZ residency rules or consent serve other jurisdictions.
