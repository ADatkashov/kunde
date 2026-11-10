# 25 — Business Process Diagrams

Diagrams are target processes; category/legal/provider rules can add branches. `Pending` is not successful completion. Payment and business records remain separate (PRD/Architecture).

## Customer acquisition and partner onboarding

```mermaid
flowchart TD
 A[Define serviceable category and zone] --> B[Verify supply and customer value]
 B --> C[Choose opt-in acquisition channel]
 C --> D[Measure qualified visits and completed transactions]
 D --> E{Contribution and quality gates met?}
 E -->|No| F[Adjust or pause spend]
 E -->|Yes| G[Expand controlled cohort]
 P[Partner registers] --> V[Identity and business review]
 V -->|Need information| N[Request evidence]
 N --> V
 V -->|Approved| T[Contract and beneficiary verification]
 T --> S[Location catalog training and test transaction]
 S --> R{Operations readiness?}
 R -->|No| S
 R -->|Yes| ACTIVE[Activate scoped category/location]
```

## Order fulfillment and delivery

```mermaid
sequenceDiagram
 participant C as Customer
 participant K as KUNDE
 participant M as Merchant
 participant L as Logistics provider
 participant F as Finance/payment provider
 C->>K: Confirm quote
 K->>F: Create payment attempt
 F-->>K: Verified result or unknown
 K->>M: Submit order idempotently
 M-->>K: Accept/reject/timeout
 alt Accepted and delivery requested
 K->>L: Request courier assignment
 L-->>K: Assign/no provider
 L->>M: Pickup
 L->>C: Drop-off with evidence
 else Rejected or no provider
 K->>F: Void/refund as verified state requires
 end
 K-->>C: Show order and payment states separately
```

## Booking fulfillment

```mermaid
flowchart TD
 A[Consumer chooses service and slot] --> H[Create expiring slot hold]
 H -->|Unavailable| A
 H -->|Held| Q[Review beneficiary price and policy]
 Q --> C{User confirms?}
 C -->|No| X[Release/expire hold]
 C -->|Yes| P{Payment required?}
 P -->|Yes| PV[Verify payment state]
 P -->|No| R[Request provider confirmation]
 PV -->|Verified| R
 PV -->|Unknown/failed| REC[Reconcile; do not confirm booking]
 R -->|Confirmed| DONE[Notify and remind if opted in]
 R -->|Rejected/timeout| REF[Release slot; compensate payment]
```

## Payment, settlement and provider payout

```mermaid
flowchart LR
 C[Customer authorizes] --> PSP[Licensed payment provider]
 PSP --> K[Verified payment event/query]
 K --> J[Immutable payment/journal entry]
 J --> O[Order/booking link]
 J --> ST[Settlement reconciliation]
 ST -->|Match| PAY[Partner/provider payable]
 ST -->|Mismatch| EX[Finance exception queue]
 PAY --> BANK[Provider settlement rail]
 BANK -->|Confirmed| PAID[Paid state]
 BANK -->|Failed| HOLD[Pending, verify beneficiary, retry by policy]
```

## Refund, dispute and support

```mermaid
flowchart TD
 CASE[Complaint or cancellation] --> AUTH[Check actor state policy and evidence]
 AUTH --> DEC{Automated rule is deterministic?}
 DEC -->|No| HUMAN[Human support/finance review]
 DEC -->|Yes| OUT[Calculate allowed outcome]
 HUMAN --> OUT
 OUT --> OK{Authorized and confirmed?}
 OK -->|No| APPEAL[Explain options and appeal]
 OK -->|Yes| REF[Idempotent void/refund request]
 REF --> STATE{Provider confirms?}
 STATE -->|No| PEND[Keep pending and escalate]
 STATE -->|Yes| CLOSE[Update linked case and notify]
```

## Suspension and city launch

```mermaid
flowchart TD
 R[Quality/safety/compliance signal] --> TRIAGE[Human triage and evidence]
 TRIAGE --> URG{Immediate risk?}
 URG -->|Yes| HOLD[Scoped temporary hold]
 URG -->|No| NOTICE[Request response/remediation]
 HOLD --> REVIEW[Independent review and active-transaction plan]
 NOTICE --> REVIEW
 REVIEW --> DEC{Decision}
 DEC -->|Restore| ACTIVE[Reactivate with monitoring]
 DEC -->|Suspend/terminate| APPEAL[Reasoned notice and appeal]
 CITY[City proposal] --> SCORE[Demand supply legal payments support readiness]
 SCORE --> GATE{All critical gates pass?}
 GATE -->|No| DEFER[Defer and close gaps]
 GATE -->|Yes| PILOT[Limited pilot]
 PILOT --> MEASURE[Quality contribution and customer outcomes]
 MEASURE -->|Pass| EXPAND[Expand zone/category]
 MEASURE -->|Fail| PAUSE[Pause and remediate]
```

## Customer support

```mermaid
flowchart TD
 U[Customer opens in-app case] --> ID[Authorize and link transaction]
 ID --> PRI[Classify priority and owner]
 PRI --> FACT[Verify timeline payment and partner/provider evidence]
 FACT --> RES{Safe deterministic resolution?}
 RES -->|Yes| ACT[Offer/execute authorized action]
 RES -->|No| ESC[Escalate finance ops legal or safety]
 ESC --> ACT
 ACT --> UPDATE[Update case and verified transaction state]
 UPDATE --> CLOSE[Notify customer and record outcome]
```
