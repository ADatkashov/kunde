# 13 — Promotions, Discounts and Loyalty

Promotions are versioned offers with eligibility, payer, budget, start/end, market/category/partner scope, limits, stacking rules, tax/commission treatment and accounting reference. Loyalty/cashback is not MVP scope (PRD 1.0 §16); document below is a future option, not an enabled feature.

## Promotion types

| Type | Funding | Required UI/accounting |
|---|---|---|
| Promo code | KUNDE, partner or split | Show saving, eligibility, expiry and payer allocation; unique redemption key |
| First-order offer | Usually KUNDE or jointly funded | Define qualifying order, customer identity/abuse rule and budget cap |
| Partner discount | Partner | Partner approves scope and pays reimbursable discount; settlement line item |
| Sponsored offer | Partner/media budget | Label sponsored placement; organic ranking remains distinguishable |
| Delivery subsidy | KUNDE/partner/joint | Track customer delivery price, actual carrier cost and subsidy separately |
| Referral | KUNDE-funded only after terms approved | Validate referrer/referee and completed qualifying transaction; prevent self-referral |
| Loyalty points/cashback | Sponsor/funder TBD | Define liability, redemption, expiry, tax treatment, refund reversal and abuse controls before launch |

## Rules and controls

Eligible discount is calculated before confirmation and bound to quote version. Reprice invalidates promotion and requires user review. Define stacking precedence, minimum basket, caps, excluded goods/categories, city/time zone, per-customer/device/order frequency and refund treatment. Partial refund reverses proportional/funded amount by line and contract; do not convert cash refund into expiring credit without user/legal approval. Reserve budget at redemption, release on failed/cancelled order as policy states. Finance reconciles promo liability and sponsor invoice.

## Experience safeguards

Terms are readable before apply; no fake countdown, hidden minimum, or advertised discount applied to inflated base price. Sponsored result is explicitly labeled. Promotion failure leaves the user’s original order intact and shows revised total before payment. Loyalty/membership requires separate business case, consumer research and legal/tax review.
