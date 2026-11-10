# 17 — Unit Economics

No KUNDE operating results exist in these documents. All numeric scenario values below are **illustrative assumptions**, not forecast, market benchmark or target. Finance must replace them with pilot data and signed provider/partner pricing.

## Metric formulas

```text
GMV = sum(eligible customer transaction value before refunds, per agreed metric policy)
Platform revenue = earned commission + service/subscription/ad revenue recognized under contract
Take rate = platform transaction revenue / GMV (exclude taxes/pass-through according to finance policy)
Gross profit = recognized revenue - direct cost of revenue
Contribution margin = recognized revenue - payment costs - refunds/chargeback loss
                     - delivery subsidy - promotion subsidy - variable support/incentives
AOV = GMV / completed qualifying orders
CAC = acquisition spend / new activated paying customers attributable to that spend
LTV = expected contribution per customer over retention horizon (cohort-based, not GMV)
Repeat rate = customers with ≥2 completed qualifying transactions / customers with ≥1
Refund rate = refunded value / captured value; also report refund transaction rate
Cancellation rate = cancelled transactions / accepted/confirmed transactions (define denominator)
Delivery cost/order = total carrier/fulfillment expense / completed deliveries
Payment cost ratio = provider/payment cost / processed value
```

Distinguish GMV from recognized KUNDE revenue; bookings, orders, cancellations and refunds must have consistent inclusion rules. Do not double-count one order’s delivery and goods as separate GMV if platform contract says otherwise.

## Illustrative single-order scenarios

Assume a **10,000 KZT eligible order value** solely to show sensitivity. Suppose KUNDE revenue is commission and KUNDE bears listed variable costs. Seller proceeds, tax and carrier gross payout are pass-through and excluded from revenue; any delivery subsidy is KUNDE cost. Amounts are KZT/order.

| Input | Conservative | Base illustration | Optimistic |
|---|---:|---:|---:|
| Commission rate assumption | 8% | 15% | 18% |
| Platform commission revenue | 800 | 1,500 | 1,800 |
| Payment cost assumption | 2.5% GMV = 250 | 2.0% = 200 | 1.8% = 180 |
| Refund/chargeback loss assumption | 150 | 80 | 40 |
| Variable support cost | 200 | 120 | 70 |
| KUNDE delivery subsidy | 700 | 250 | 0 |
| KUNDE promotion subsidy | 400 | 150 | 50 |
| **Contribution/order** | **−900** | **700** | **1,460** |

Formula: `commission revenue − all KUNDE-borne variable costs above`. Excludes fixed payroll, cloud, legal, taxes, CAC and partner-funded discount; excludes KUNDE-funded discount already separately modeled. It is a sensitivity example, not an expected performance claim. A booking’s contribution uses completed booking fee/commission minus payment, support, acquisition incentive, cancellation/refund cost; no GMV or commission rate is assumed until category contract is known.

## Entity-level model

- **Partner:** eligible GMV × contract rate − partner-specific operating/support/integration cost − funded promotions; include activation and churn cost.
- **Customer cohort:** repeat completed transactions × contribution/transaction − CAC and retention incentives. LTV is contribution, not gross spend.
- **Delivery:** customer/merchant delivery receipt less contracted carrier cost and subsidy, plus failure/return cost; report per zone/daypart.
- **City/category:** sum cohort contribution less fixed city operations, sales, support and compliance cost; measure contribution before overhead and operating profit separately.

## Pilot data needed

Order AOV and mix; eligible commission base; partner rate acceptance; completed/order conversion; partner acceptance and cancel reasons; refund/chargeback rates and amount; carrier cost and delivery subsidy; payment pricing; support contacts/cost per transaction; promo redemption/funder; CAC by channel/cohort; 30/60/90-day repeat; partner acquisition/activation costs; provider earnings and payout failure; category-specific booking lead time/no-show. Capture privacy-minimized cohort data and account for seasonality.
