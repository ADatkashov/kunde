# 07 — Acceptance Criteria

Criteria use observable outcomes and are mapped to story IDs from document 03. Given/When/Then scenarios are release gates; unspecified policy values remain configuration inputs, not invented constants.

| AC | Story / requirement | Acceptance criteria |
|---|---|---|
| AC-01 | HOME-001 | Given location permission is denied, when user selects location, then manual address search remains available; selected location is visible and applied to subsequent results. |
| AC-02 | HOME-002 | Given supported and unsupported categories, when Home loads, then only supported categories are actionable; loading, empty and recoverable error states are distinguishable. |
| AC-03 | HOME-003 | Given no eligible nearby supply, when recommendations load, then the app shows a clear empty state and does not fabricate providers or availability. |
| AC-04 | HOME-004 | Given an expired/ineligible promotion, when checkout validates it, then discount is removed with explanation and revised total is shown before payment confirmation. |
| AC-05 | EXP-001 | Given category browsing, when user opens a listing, then provider identity, service area, price model, availability, relevant rules and support path are present. |
| AC-06 | EXP-002 | Given filters/sort, when applied, then results satisfy selected filters and empty state offers filter reset; sort is deterministic for equal values. |
| AC-07 | EXP-003 | Given listing data changed since view, when user proceeds, then server revalidates and presents changed terms before any commitment. |
| AC-08 | AUTH-001 | Given a valid phone, when verified challenge is submitted before expiry, then one account/session is created; expired, replayed, invalid and over-limit attempts do not authenticate. |
| AC-09 | AUTH-002 | Given revoked/expired session, when mutation is attempted, then server denies it; after recovery, prior idempotency key can be queried without repeating charge. |
| AC-10 | USER-001 | Given locale/profile update, when valid fields save, then new values display consistently; contact change stays pending until verification. |
| AC-11 | USER-002 | Given an address outside service area, when checkout is attempted, then order cannot proceed and user may choose another valid address. |
| AC-12 | USER-003 | Given marketing is disabled, when campaign is sent, then user is excluded; required transaction/security notices remain governed separately. |
| AC-13 | USER-004 | Given deletion request, when accepted, then request status and retention explanation are shown; eligible data is removed/de-identified and restricted records remain access-controlled. |
| AC-14 | FAM-001 | Given a family invite, when accepted, then member sees only granted family data; revocation removes future access and invalidates cached authorization. |
| AC-15 | FAM-002 | Given dependent booking without valid guardian/delegation grant, when submitted, then it is blocked and no child data is sent to provider. |
| AC-16 | ORDER-001 | Given cart line/price/availability changes, when checkout validates, then current itemized total is shown; no stale total is charged. |
| AC-17 | ORDER-002 | Given same placement request retried, when idempotency key/payload match, then exactly one order/payment attempt exists; mismatched payload is rejected. |
| AC-18 | ORDER-003 | Given partner rejection or dispatch timeout, when deadline expires, then customer sees failed/cancelled status, next step and payment compensation state. |
| AC-19 | BOOK-001 | Given two users request the final slot concurrently, when holds are created, then at most one active hold exists and loser must choose another slot. |
| AC-20 | BOOK-002 | Given cancellation/reschedule request, when policy is applied, then fee/refund estimate and old/new slot effect appear before confirmation. |
| AC-21 | PAY-001 | Given delayed provider confirmation, when payment is queried, then UI says pending/checking; it never labels unverified payment paid or requests duplicate payment. |
| AC-22 | ACT-001 | Given mixed transaction history, when filtered, then order/booking/payment states remain distinct and each detail links to associated records. |
| AC-23 | SUP-001 | Given a user opens a transaction case, when submitted twice with same key, then one case exists and only authorized parties can read it. |
| AC-24 | AI-001 | Given a discovery question, when AI answers, then service facts are sourced from current authorized data and estimates/uncertainties are labeled. |
| AC-25 | AI-002 | Given AI prepared an order/booking, when user reviews, then provider, items/service, beneficiary, location, price, terms and expiry are visible; draft is not yet committed. |
| AC-26 | AI-003 | Given action draft changes after user approval, when execution is attempted, then old approval is invalid and fresh confirmation is required. |
| AC-27 | AI-005 | Given user deletes AI context, when deletion completes, then eligible context is removed; immutable transaction/audit records remain outside conversational retrieval. |
| AC-28 | PARTNER-001 | Given business is unverified or suspended, when consumer discovery runs, then it is not orderable; owner sees verification status and remediation. |
| AC-29 | PARTNER-002 | Given employee lacks location/order grant, when command is sent, then server denies it and records security event; valid repeated command is idempotent. |
| AC-30 | PROVIDER-001 | Given task is reassigned/revoked, when old provider updates status, then update is denied and assignment/customer data access expires. |
| AC-31 | OPS-001 | Given support access without a case/purpose, when record lookup occurs, then access is denied; authorized access records purpose, actor and fields/actions. |
| AC-32 | OPS-002 | Given report is reviewed, when moderator acts, then reason/policy and appeal path are recorded; moderator cannot issue refund absent separate grant. |
| AC-33 | FIN-001 | Given provider event mismatches internal amount/state, when reconciliation runs, then no silent ledger edit occurs; item is quarantined and assigned for review. |
| AC-34 | ADMIN-001 | Given privilege elevation, when not approved/expired, then action is denied; break-glass use has reason, time limit, immutable audit and review trigger. |
| AC-35 | AI-004 | Given an AI tool request, when it attempts a forbidden ledger write, state bypass, permission change or out-of-scope read, then the platform denies it, records a security event and leaves protected records unchanged. |

## Cross-cutting release acceptance

- Every requirement in document 05 is linked to at least one AC in `24-requirements-traceability.md`.
- Negative paths, unauthorized transitions, duplicate requests and delayed external results are exercised before a category pilot.
- Customer-visible status matches persisted server state and verified external state; unknown state is shown as pending.
- Each screen has loading, empty and error behavior; sensitive flows revalidate online.
