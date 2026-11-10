# 24 — Operational Playbooks

Playbooks require named on-call queues, internal systems and approved policy values before launch. “TBD” timers must be set to match contracts, law and staffed coverage. Every case records actor, reason, evidence ref, state and correlation ID.

## PB-01 Partner onboarding

**Trigger:** new business application. **Responsible:** Partner Operations. **Steps:** check completeness → identity/business validation → duplicate/prohibited category review → bank beneficiary verification by approved process → contract/category approval → location/catalog setup → training/test transaction → readiness checklist. **Decision:** approve, request info, reject, escalate. **Escalation:** Compliance/Finance for ambiguous identity/payment; Legal for license. **Outcome:** scoped ACTIVE or reasoned pending/reject. **Audit:** document access, decision and approver.

## PB-02 Partner verification/expiry

**Trigger:** document expiry, ownership/beneficiary change or risk alert. **Responsible:** Trust/Partner Ops. **Steps:** flag affected scope → restrict new transactions if required → request updated evidence → review independently → update role/eligibility. **Decision:** maintain, limit, suspend. **Escalation:** Compliance. **Outcome:** current status and affected listing/customer notice. **Audit:** previous/new state and reviewer.

## PB-03 Partner suspension/appeal

**Trigger:** safety, fraud, repeated failures, legal or data breach. **Responsible:** Operations with Trust/Compliance. **Steps:** preserve evidence → determine urgent risk → apply least-disruptive hold → protect active orders → notify partner where safe → review response → human decision/appeal. **Decision:** restore, limited, terminate. **Escalation:** Legal/Security for severe cases. **Outcome:** no stranded transactions; appeal tracked. **Audit:** reason, policy, approval and timeline.

## PB-04 Provider verification

**Trigger:** new provider/document renewal. **Responsible:** Provider Operations. **Steps:** verify identity and category eligibility → check required documents → define zone/role → train safe status workflow → activate. **Decision:** approve/need-info/reject. **Escalation:** Compliance for regulated work. **Outcome:** assigned-role grant only. **Audit:** evidence refs and expiry.

## PB-05 Order failure / partner rejection

**Trigger:** rejection, timeout, partner disconnect or order/payment mismatch. **Responsible:** Order Operations. **Steps:** query canonical state → verify payment → contact authorized partner → determine alternate only with user consent → cancel/compensate if not fulfillable → notify consumer. **Decision:** reassign, wait, cancel. **Escalation:** Finance for unknown/paid orphan, support for customer impact. **Outcome:** verified status and open refund if owed. **Audit:** every attempt and event.

## PB-06 Delivery delay/failed delivery

**Trigger:** missed estimate, no provider, address issue, customer unavailable. **Responsible:** Logistics Ops. **Steps:** verify last event → contact carrier/merchant → message customer with known facts/options → retry/return/cancel according to contract → capture evidence → settle cost/refund allocation. **Decision:** safe retry, return, cancel. **Escalation:** safety incident to incident lead. **Outcome:** item location and financial state known. **Audit:** timestamps, provider response and customer choice.

## PB-07 Customer complaint

**Trigger:** case opened. **Responsible:** Support. **Steps:** authenticate/authorize requester → link transaction → classify priority → read status/evidence → state known/unknown → offer allowed next steps → monitor due time. **Decision:** resolve, refund review, partner/provider response, escalate. **Escalation:** P0/P1 and legal/privacy. **Outcome:** customer receives update and case closure reason. **Audit:** access purpose and communication.

## PB-08 Refund request

**Trigger:** approved cancellation/quality remedy/duplicate charge. **Responsible:** Finance for money; Support owns case. **Steps:** validate captured balance and prior refunds → policy/reason evidence → approval/dual-control if required → idempotent provider command → reconcile verified result → notify user. **Decision:** full/partial/no refund by authorized actor. **Escalation:** provider failure/dispute. **Outcome:** immutable journal and refund state. **Audit:** amount/currency, approver, provider reference.

## PB-09 Payment failure/unknown state

**Trigger:** timeout, duplicate, webhook mismatch or order creation failure. **Responsible:** Finance/Payment Ops. **Steps:** do not prompt duplicate payment → lookup by idempotency/provider ref → verify webhook signature/amount → reconcile → retry safe persistence/compensation → create high-priority incident if mismatch. **Decision:** confirmed, failed, pending, duplicate. **Escalation:** provider/engineering. **Outcome:** user-facing verified state. **Audit:** source and event dedupe.

## PB-10 Payout failure

**Trigger:** partner/provider settlement rejected/returned. **Responsible:** Finance. **Steps:** hold payable status → verify provider code and beneficiary through secure channel → protect against bank-change fraud → request corrected data with approval → resubmit idempotently → reconcile. **Decision:** retry, hold, escalate. **Outcome:** paid or documented pending. **Audit:** maker/checker and beneficiary version.

## PB-11 Fraud suspicion

**Trigger:** risk signal/report. **Responsible:** Trust with Finance/Security as needed. **Steps:** preserve minimal evidence → scope risk → temporary proportionate restriction → human review → contact affected party when safe → release/maintain/terminate → handle affected funds under policy. **Decision:** no irreversible action by model alone. **Escalation:** counsel/law enforcement only through authorized process. **Outcome:** reasoned decision and appeal. **Audit:** evidence access and action.

## PB-12 Dispute and emergency

**Trigger:** contested transaction, chargeback, safety emergency or legal notice. **Responsible:** Case lead assigned by type. **Steps:** preserve deadlines/evidence → verify safety → suspend unsafe fulfillment if necessary → notify relevant owner → distinguish provider chargeback from internal complaint → assign human decision maker → communicate verified result. **Escalation:** immediate Finance/Legal/Security for critical event. **Outcome:** documented action, customer/partner next step, lessons review. **Audit:** access, decision and deadline trail.
