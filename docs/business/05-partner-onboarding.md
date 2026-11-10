# 05 — Partner Onboarding and Verification

## Workflow and states

```text
INVITED/STARTED → PROFILE_SUBMITTED → DOCUMENTS_PENDING → UNDER_REVIEW
→ NEEDS_INFORMATION ↔ RESUBMITTED → VERIFIED → CONTRACT_PENDING
→ SETTLEMENT_SETUP_PENDING → CATALOG_SETUP → TESTING → ACTIVE
Alternative outcomes: REJECTED, SUSPENDED, EXPIRED, TERMINATED
```

`ACTIVE` requires all applicable identity/legal verification, executed agreement, verified settlement beneficiary, category approval, published catalog, location/hours, trained authorized users, support contacts, test transaction and operational readiness. Verification approval alone does not make a listing available.

## Step-by-step checklist

1. Account registration and verified owner contact; create business draft.
2. Capture legal/trading name, legal form, registration/tax identifiers only as approved, operating contacts, beneficial-owner/authorized-representative evidence as required.
3. Collect business and representative documents through secure private upload; record document type, issuer, expiry, reviewer and hash/reference.
4. Validate identity/business status using approved sources/process; check duplicate/sanction/prohibited category per compliance program.
5. Verify settlement beneficiary/bank account name match using licensed payment/financial provider process; mask details; no email-based unverified bank changes.
6. Present category contract, commercial terms, data responsibilities, consumer/refund service levels and agreement version; capture authorized acceptance.
7. Approve category/service scope, locations and service zones; configure branch hours, catalog, price model, inventory/capacity, cancellation terms and authorized staff roles.
8. Complete role-based training and sandbox/test order/booking/refund/cancellation; validate contact/escalation.
9. Operations owner signs launch checklist; activate by location/category, with monitoring and rollback.

## Review outcomes

Need-info response states exact missing/expired/inconsistent evidence, safe resubmission route, owner and target response window (TBD). Reject with policy reason code, record reviewer and appeal path; do not expose fraud detection rule details. Re-verification on expiry, ownership/legal entity/settlement change, suspicious activity, category change or risk trigger. Suspension prevents new discovery/requests as policy defines, preserves active work/customer support, freezes risky settlement changes as counsel/finance authorize and starts case review.

## Controls and audit

Separate submitter/reviewer/finance approval where feasible. All document access, status decision, bank detail changes, contract acceptance, category activation and suspension record actor, role, reason, evidence reference, timestamp and previous/new status. Store only necessary documents, access narrowly, retention per legal policy. Uploaded documents must be encrypted, private and malware-scanned where feasible. Appeal decisions by different reviewer where capacity allows.
