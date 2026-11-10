# 12 — Cancellation, Refunds and Disputes

This policy framework is category-aware. Exact windows, amounts, exceptions, legal rights and evidence requirements are open decisions for product, finance, partners and counsel; no arbitrary universal refund promise is made.

| Scenario | Decision path | Financial handling / customer outcome |
|---|---|---|
| Customer cancels before partner accepts | Automated eligibility check by current category/policy/state | Release/void authorization; disclose any applicable fee before confirmation |
| Customer cancels after fulfillment starts | Calculate policy and completed portion; user confirms request | Full/partial/no refund based on validated policy; uncertain case to human review |
| Partner cancels/rejects | Record reason, release slot/stock, notify customer | Void or full refund for undelivered portion unless law/contract requires otherwise |
| Provider cancels or cannot fulfill | Reassign only if user-visible policy permits and time remains | Offer reassignment or cancellation; do not silently change provider/service/price |
| Platform cancels for safety/availability | Authorized operator action with reason and evidence | Compensation follows policy; audit and notification mandatory |
| Partial fulfillment / missing item | Preserve ordered vs fulfilled line items and evidence | Line-level or proportional remedy only under approved rules; no fabricated delivery proof |
| Incorrect/poor-quality service | Support case with category-specific evidence, response window and provider reply | Human review for contested claims; record rationale and appeal path |
| Delivery failure/delay | Verify provider events and delivery evidence | Offer updated ETA, cancellation where applicable, or review; do not mark delivered from unverified signal |
| No-show / late cancellation | Apply disclosed grace period, party evidence and provider policy | Automated outcome only where rules are objective; disputed cases human-reviewed |
| Duplicate charge | Compare provider and platform transaction references | Confirm duplicate, reverse/refund duplicate; prioritize finance queue |
| Chargeback/payment dispute | Link provider/network case and preserve evidence | Freeze conflicting manual refund actions; authorized finance review and deadline tracking |
| Refund operation fails | Keep refund pending/failed with retry schedule and case | Notify user of pending resolution; never represent failure as completed refund |

## Resolution workflow

1. Validate actor, transaction link, current state, policy version and time.
2. Capture reason code and user evidence with minimum necessary data.
3. Show eligible outcome and estimate; require confirmation for customer-initiated mutation.
4. Persist cancellation/dispute action before external money command; assign correlation/idempotency reference.
5. Keep transaction status separate from payment/refund status.
6. Retry transient provider operation idempotently; escalate after configured attempts/age.
7. Notify consumer and affected partner/provider with role-minimized information.
8. Record reviewer identity, evidence, decision and appeal route for manual decisions.

Refund ledger entries are immutable. Support agents may propose or issue only within explicit amount/role limits. Finance review and possible dual control are recommended for high-value or manual exceptions; threshold is TBD. Human review is required for contested quality, fraud, chargeback, unclear evidence, policy exceptions and conflicting provider signals.
