# 07 — Driver and Provider Operations

Providers include drivers, couriers and independent service professionals; onboarding, eligibility and dispatch differ by activity and applicable law. KUNDE does not assume employment/contractor classification; obtain legal review before operating model is set.

## Lifecycle

Registration → identity/eligibility → category qualification/documents → service zone and availability → assignment offer → accept/reject/expire → task execution → completion/evidence → earnings/reconciliation → review/complaint → re-verification, suspension/appeal or termination.

| Role | Qualification and data shown | Assignment behavior | Performance dimensions |
|---|---|---|---|
| Driver | Identity, driving/vehicle eligibility as legally required; trip pickup/drop-off and passenger details only after assignment | Offer contains service class, pickup/destination/time/fare basis; accept/decline; safe trip status | Eligible availability, acceptance/completion, cancellations, safety incidents, customer feedback |
| Courier | Identity and delivery eligibility; package handling requirements; pickup/drop-off instructions | Offer has package essentials, area, deadline and compensation basis; scan/proof if policy supports | Pickup accuracy, delivery success, delay/incident, return handling |
| Service professional | Identity, skill/credential/licence as category requires; job scope/address/access only for assigned work | Provider may accept inspection/quote request; no work or extra charge before user accepts final scope | Arrival, completion, quote variance, dispute/quality and credential expiry |

## Automated vs human decisions

**Automate:** document expiry reminders; eligibility status checks against approved sources; assignment matching by zone/capacity/availability; deadline expiry; duplicate command protection; payout status sync; low-risk anomaly flagging. Matching must be explainable enough for operations and not use prohibited/discriminatory factors.

**Human review:** ambiguous identity/credential result, safety incident, suspected fraud, contested quality/no-show, payout beneficiary change, suspension/termination, appeal, legal/medical compliance and adverse action. AI may summarize permitted case facts but cannot decide or impose consequential action without authorized reviewer.

## Assignment and accountability

Offers have explicit expiry/terms and are idempotent. Rejection does not create a customer-visible fulfillment claim. On acceptance, reveal minimum data; access expires at cancellation/completion/assignment withdrawal. Reassignment invalidates prior provider access. Offline events retain expected version and reconcile; revoked provider cannot complete. Incident contact channel and emergency procedure are category-specific and must be agreed before activation.

## Earnings, conduct and appeals

Provider earnings are calculated from completed eligible work and contract terms, less only lawful/disclosed adjustments. Show gross task amount, deductions/reasons, pending vs eligible vs paid and payout reference; do not present estimated earnings as settled cash. Complaints are case-linked and allow provider response. Suspension notice includes reason category, effect on new assignments and appeal path unless urgent safety/legal hold limits notice; final decisions are human-reviewed and audited.
