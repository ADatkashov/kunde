# 03 — Commission and Pricing Strategy

## Configurable price rule

Every commercial rule is versioned by country/city, category/subcategory, partner, fulfillment model and effective interval. Specific partner contract may override category default only with authorized approval and audit. Quote snapshot stores line items, payer, payee, tax/fee basis, discount funding split, commission basis/cap/floor, currency, policy version and expiry. No rule may retroactively change a confirmed quote except legally/contractually permitted correction with user approval.

Illustrative commission formula:

```text
commission_base = contract_defined_eligible_amount(order)
gross_commission = commission_base * rate + fixed_component
commission_due = clamp(gross_commission, minimum, maximum)
adjustment = commission_due * refundable_eligible_share (per contract)
net_commission = commission_due - adjustments + approved_contract_adjustments
partner_payable = captured_partner_amount - net_commission - contracted_partner_fees
                 + partner_funded_discounts - KUNDE_funded_reimbursements
```

Formula inputs/discount treatment are contract choices; avoid double deduction. Taxes/processor fees may not be part of commission base unless contract and counsel explicitly define them.

## Scenario ranges for financial modelling only

The ranges below are **KUNDE planning hypotheses, not observed market rates, legal recommendations or offers to partners**. They are wide enough for scenario testing; replace them with partner economics, competitor/public price research, fulfillment cost, customer conversion and signed negotiation results. Percentage means illustrative share of eligible transaction value before taxes/pass-through unless otherwise agreed.

| Segment | Hypothesis range | Possible model / validation need |
|---|---:|---|
| Restaurants/cafes | 10–22% | Commission sensitivity vs merchant margin, delivery responsibility and order incrementality |
| Grocery/supermarket | 5–14% | Lower-margin basket; test fixed/order fee or fulfillment fee separately |
| Retail | 7–18% | Category/brand margin varies widely; test lead vs transaction fee |
| Taxi/mobility | 8–20% | Determine whether percentage, fixed trip fee or contracted dispatch fee is lawful and viable |
| Courier/delivery | 8–20% | Separate merchant commission from customer delivery payment and courier earnings |
| Home services | 8–20% | Success fee on completed accepted quote vs lead fee; account for off-platform leakage |
| Health providers | 0–12% illustrative only | **Do not price/launch transaction fee until health advertising/referral/fee restrictions reviewed by counsel** |
| Personal care | 8–20% | Commission vs appointment SaaS, deposits and repeat client economics |
| Education | 5–15% | Enrollment fee vs subscription; refunds/term withdrawal and child safeguarding costs |
| Experiences/tickets | 5–18% | Per-ticket fee vs organizer commission; inventory, issuance and cancellation liability |
| Auto services | 7–18% | Qualified lead or completed job commission; inspection and extra work rules |

These ranges are deliberately **illustrative**, not validation. Do not set an actual partner quote from them without research/approval.

## Other price components

- Fixed KUNDE service fee: optional; test transparent fixed amount vs percentage, ensure payment/compliance role is approved.
- Delivery price: distance/time/zone/provider quote or merchant-funded subsidy; disclose estimate and expiry. Avoid double-charging merchant and consumer without contract clarity.
- Minimum/maximum commission: protects tiny/large transaction economics; publish in partner terms and display customer price impact when applicable.
- Regional/time promotions: time-bounded, nonretroactive, funded by KUNDE/partner/joint ledger split.
- Partner subscription: per location/seat/tool only if functionality exists and cancellation terms are clear.

## Pricing governance

Commercial owner proposes; finance models category contribution; legal reviews consumer/partner disclosure and tax; operations validates ability to deliver; authorized approver publishes versioned rule. Monitor acceptance, conversion, net commission, partner churn, refunds, incremental demand and complaints. Roll back future quotes if unfair/unviable; honor prior quote snapshots.
