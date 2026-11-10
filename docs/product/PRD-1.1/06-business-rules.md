# 06 — Business Rules

These recommendations apply consistently unless a category policy explicitly overrides them. Monetary and cancellation policy values are intentionally configurable and unresolved until confirmed by product, finance, partners and legal.

| ID | Rule |
|---|---|
| BR-001 | One authenticated identity owns personal data. Family membership, business role, provider role and platform role are separate grants with explicit scope and revocation. |
| BR-002 | A listing is actionable only when active, verified as required, within its service area, currently available, and backed by a fulfillment/support process. |
| BR-003 | Quote shown at checkout is a versioned snapshot with currency, line items, taxes/fees where applicable, discounts, fulfillment cost, total and expiry. Any material change requires renewed user review. |
| BR-004 | Cart is scoped to one merchant/order fulfillment context unless a future explicitly designed multi-merchant checkout is approved. |
| BR-005 | A payment is not successful until its provider state is verified. A request timeout is `UNKNOWN/PROCESSING`, never an assumed failure or success. |
| BR-006 | Each mutating API command accepts an idempotency key scoped to principal and operation. Reusing key with same payload returns original result; different payload is rejected. |
| BR-007 | Order/booking/payment are separate linked resources. A payment may be authorized before an order is accepted; eventual failure must create compensating void/refund work, not erase records. |
| BR-008 | Server is authoritative for status, price, role, slot availability and payment state. Client timestamps or AI claims cannot authorize transitions. |
| BR-009 | Order transitions must match document 09; booking transitions document 10; payment transitions document 11. Terminal states do not reopen; corrections are appended as compensating records/events. |
| BR-010 | Partner/provider response and fulfillment deadlines are configured per category/contract and shown where they affect the customer. No single SLA is assumed. |
| BR-011 | Cancellation outcome is calculated from current state, category policy version, actor and time; user sees amount/fees before confirmation when calculable. |
| BR-012 | Refund amounts cannot exceed captured amount less prior completed refunds; partial refunds reference line items or documented reason. Provider acceptance is not proof that refund settled. |
| BR-013 | Ratings can be submitted only for eligible completed transaction, once per applicable subject; moderation is separate from rating ownership. |
| BR-014 | Customer/provider communication uses controlled channels; direct contact data is not exposed unless operation and law require it. |
| BR-015 | AI context is permission-filtered and purpose-limited. Tool execution repeats authorization and validation independent of model output. |
| BR-016 | A confirmation binds to exact action draft version, user, amount, beneficiary, target, terms and expiry. Any change invalidates the confirmation. |
| BR-017 | If category availability, price or provider assignment changes before commitment, stop and ask user to choose or approve an updated option. |
| BR-018 | Critical audit entries are append-only and include actor, role/scope, action, prior/new state, reason, timestamp and correlation IDs; secrets and unnecessary sensitive values are excluded. |
| BR-019 | Marketing consent is independent of service notification settings. No promotional messaging without applicable consent; transactional/security notices follow service needs and law. |
| BR-020 | Store timestamps in UTC instants; local display uses service location zone. Money is stored as integer minor units with ISO currency code. |
| BR-021 | Deletion requests remove or de-identify data where permitted; legal/financial records under approved retention are restricted and explained, not silently erased. |
| BR-022 | Health, child and precise location data are sensitive. Collect only what the selected transaction requires; access is purpose-bound and logged. |
| BR-023 | Manual admin correction never rewrites history. It creates a reasoned compensating action subject to role separation and, for money, dual-control policy to be validated. |
| BR-024 | Cross-category plans are proposals until each component is independently validated and confirmed; partial completion is reported accurately. |

## Price and capacity behavior by category

- Food: item/menu prices and inventory are revalidated before payment and merchant acceptance; substitutions require prior user preference/consent.
- Mobility: estimates expire and may differ from final fare only under disclosed pricing rule; destination or material fare change gets renewed consent.
- Home: estimate is not a binding quote; final scope/price needs user acceptance before work begins.
- Personal care/health: slot, resource and duration are reserved atomically; provider confirmation deadline is explicit.
- Experiences: inventory is locked/confirmed by source; ticket issuance failure follows payment compensation.
- Auto: inspection-dependent estimate cannot be represented as final price.
- Family: guardian/delegated authority and beneficiary are verified before sharing relevant details.

Related: `09-order-lifecycle.md` through `13-permissions-and-access-control.md`.
