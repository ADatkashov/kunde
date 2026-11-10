# 10 — Refunds, Cancellations and Disputes

Exact deadlines, statutory rights and refund allocation vary by category/contract and require Kazakh counsel and partner approval. These are process rules, not consumer contract terms. Refund status is distinct from order/booking status (PRD 1.1 §§09–12).

| Scenario | Initial owner / evidence | Proposed financial treatment | Review/appeal |
|---|---|---|---|
| Customer cancels before acceptance | Customer request, current state/time | Void authorization or full refund if captured, subject to law/terms | Automated when deterministic; support if state conflicts |
| After partner acceptance, before work | Customer/partner timeline and policy | Apply disclosed category cancellation rule; partner cancellation generally not charged to consumer absent valid basis | Human review if fee contested |
| During fulfillment | Fulfillment evidence, completed portion | Partial/no refund only under approved policy and law | Support review, consumer reply and appeal |
| After completion / poor service | Consumer description, order/booking proof, partner response | No automatic denial; partial/full remedy based on evidence/contract/law | Human decision; independent appeal for contested case |
| Partner cancels/rejects | Partner reason and accepted state | Consumer notifies; void/refund undelivered amount; commission reversal per contract | Escalate repeated partner failures |
| Provider cancels/no-show | Assignment, provider/customer timestamps and contact attempts | Reassign only with consent/time; otherwise void/refund under policy | Human review for disputed no-show |
| Missing/incorrect/damaged goods | Line item, permitted photo/order evidence, merchant response | Line-level replacement/refund/credit only if user agrees and policy supports | Escalate food safety/safety or disputed evidence |
| Late delivery | Verified pickup/status/ETA and user preference | Offer revised estimate/cancel option when policy allows; refund delivery fee only per approved rule | Support if no verified ETA or material impact |
| Booking slot unavailable / provider fails | Hold/confirmation events | No confirmed slot if unavailable; void/refund paid deposit | Human if provider state conflicts |
| No-show / late cancellation | Disclosed deadline, check-in/attendance evidence | Apply only approved, evidence-backed policy; no automatic inference from app inactivity | Human review/appeal available |
| Duplicate charge/payment disputed | Provider reference and statement | Reverse/refund duplicate; avoid double refund while chargeback open | Finance and provider dispute process |
| Refund rejected or delayed | Provider result/reason | Keep pending/failed, retry idempotently, finance queue; never mark complete | Escalate to payment provider/finance; customer update |

## Case handling sequence

Open linked case → preserve event timeline/evidence → determine customer/partner/provider facts → apply versioned rule and confirm consequences → record cancellation/dispute state → initiate void/refund or replacement → wait for verified provider outcome → notify all authorized parties → appeal/reopen via new case record, not overwritten history. Evidence is purpose-limited and redacted. AI may classify/prepare a summary but cannot decide liability or issue money without authorized human/policy action.

## Time targets

Every operational target is **TBD** pending payment contract, consumer law, partner SLA and staffing. Product must publish a customer-facing estimate only when support/finance can meet it; internal escalation timers are configured by severity and provider deadline. Statutory deadlines override internal targets.
