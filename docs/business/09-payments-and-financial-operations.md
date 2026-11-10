# 09 — Payments and Financial Operations

This is an operating design, not an authorization to hold/process funds. The Kazakhstan Law on Payments and Payment Systems regulates payment services and states applicable authorization/registration requirements; exact applicability to KUNDE’s proposed role and agency arrangement must be determined by Kazakh counsel and a licensed payment specialist ([Adilet law](https://old.adilet.zan.kz/eng/docs/Z1600000011)). Use a licensed/appropriately authorized provider; do not launch wallet, escrow, payment aggregation or cash collection without legal basis and provider contract.

## Roles and funds flow

For each category define seller/service provider, customer payer, payment provider/acquirer, settlement beneficiary, KUNDE’s contractual role, refunds owner and merchant of record before launch. Preferred initial flow is provider-hosted/tokenized consumer payment to the relevant seller/beneficiary with a contractually supported split/settlement, or another structure approved by counsel. Do not assume KUNDE can receive gross customer funds and later remit them.

## Accounting records

Separate immutable records for payment attempt, authorization, capture, void, refund, chargeback, fee, commission, promotion subsidy, provider earning, partner payable, settlement and reconciliation adjustment. Every entry has transaction/provider references, currency, amount in minor units, state, effective/posted time, counterparty, reason and correlation/idempotency key. Never overwrite a posted financial entry; use reversing/compensating record. Finance confirms whether double-entry ledger and principal/agent presentation are required.

## Transaction sequence

1. Quote freezes who charges what, currency, taxes/fees where validated, promotion payer, commission basis and expiry.
2. Consumer authorizes exact amount through payment provider; KUNDE persists attempt and idempotency reference.
3. Provider-signed/verified event or authoritative status query updates payment state. Unknown stays pending.
4. Fulfillment request is submitted independently; partner/provider acceptance is not a payment state.
5. Capture timing follows provider capabilities/category contract; authorization is not captured cash.
6. On rejection/failure, void authorization or request refund of captured funds; keep refund pending until provider confirmation.
7. Settlement statement is reconciled to internal journal at agreed cadence; mismatch enters finance exception queue.

## Partner and provider payable

Illustrative calculation only:

```text
partner_payable = eligible_captured_sales
                  - contract_commission
                  - approved_partner_borne_fees/refunds/adjustments
                  + partner_funded_discount_reimbursement
                  - prior_paid/withheld amounts
```

Provider earnings and payout are a separate sub-ledger. Delivery fee is allocated to the party that actually provides/contracted the delivery; KUNDE-funded promotion subsidy is a separate receivable/cost, never silently deducted from partner. Reconciliation checks provider gross/currency, order linkage, captured/void/refund totals, commission version, settlement amount and duplicate statement lines.

## Operational exceptions

Duplicate payment: identify via provider ref/idempotency and reverse duplicate. Payment succeeded/order missing: recovery case and void/refund, customer notice. Chargeback: freeze conflicting manual refund action, preserve evidence/deadline, assign finance. Payout failure: keep payable status pending, verify beneficiary through controlled process, notify recipient, never alter bank details from email request alone. Cash: not in MVP by default; would require collection accountability, receipt, reconciliation, fraud and refund model first.

## Controls and reporting

Dual control is recommended for manual high-value adjustments/beneficiary change; thresholds TBD. Daily/contract-period reconciliation and aged exception reporting. Payment provider license/status, split-pay capability, chargeback evidence, webhook security, settlement timing, fees, reserves, prohibited categories, data location and support SLA verified before contract. Report GMV, captured funds, platform revenue, partner payable and cash-in-transit as separate measures.
