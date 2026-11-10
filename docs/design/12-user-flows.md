# 12 — User Flows

The flows reflect PRD 1.1 and architecture: state is server-authoritative, mutations are idempotent, payment confirmation is verified, and AI confirmation is specific to a draft. “Continue” never means success until the result is confirmed.

## Registration, login, OTP and onboarding

```mermaid
flowchart TD
 G[Guest opens KUNDE] --> R{Create account or sign in?}
 R -->|Register| P[Enter phone and consent]
 R -->|Sign in| L[Enter phone]
 P --> O[Request OTP]
 L --> O
 O --> V{Code valid and current?}
 V -->|No| X[Explain expiry or retry limit; resend/support]
 X --> O
 V -->|Yes| A[Create or authenticate session]
 A --> PR{Optional profile details complete?}
 PR -->|No| SK[Skip nonrequired details]
 PR -->|Yes| SAVE[Save validated profile and locale]
 SK --> LOC[Select city/address manually or allow location]
 SAVE --> LOC
 LOC --> HOME[Home with only operational categories]
```

No phone-account enumeration before verification. OTP cooldown and session expiry use states in doc 14. Onboarding can be skipped except required consent/security steps.

## Address, global search, category, business and product

```mermaid
flowchart TD
 H[Home or Explore] --> ADR{Location available?}
 ADR -->|No permission/no saved address| MAN[Manual address or city selection]
 ADR -->|Yes| SEL[Confirm selected service area]
 MAN --> SEL
 SEL --> Q[Enter global search or category]
 Q --> FIL[Choose category filters and sort]
 FIL --> RES{Results available?}
 RES -->|No| EMPTY[Explain no supply; preserve query; change area/filter]
 RES -->|Error| ERR[Retry; preserve query; show stale label if cached]
 RES -->|Yes| TYPE{Result type}
 TYPE --> BIZ[Business detail]
 TYPE --> SVC[Service detail]
 TYPE --> PROD[Product detail]
 BIZ --> CHOOSE[Select catalog item/service]
 PROD --> OPT[Choose options and quantity]
 SVC --> BOOK[Choose scope/staff/slot or quote]
 OPT --> VALID[Revalidate stock and price]
 CHOOSE --> VALID
 BOOK --> VALID
```

If map is unavailable, retain list/manual address. Stale search result cannot commit a transaction.

## Booking and rescheduling

```mermaid
flowchart TD
 S[Service details] --> SLOT[Choose date/staff/resource]
 SLOT --> HOLD[Request short-lived slot hold]
 HOLD --> H{Hold granted and still valid?}
 H -->|No| REFRESH[Explain slot taken/expired; refresh alternatives]
 REFRESH --> SLOT
 H -->|Yes| REVIEW[Review service, beneficiary, time zone, price and policy]
 REVIEW --> CONF{Confirm booking?}
 CONF -->|No| RELEASE[Release hold or let it expire]
 CONF -->|Yes| PAY{Payment required?}
 PAY -->|No| REQ[Submit confirmation request]
 PAY -->|Yes| CHARGE[Authorize/capture via payment flow]
 CHARGE --> PV{Provider payment verified?}
 PV -->|No or unknown| PEND[Show pending; reconcile; do not retry charge blindly]
 PV -->|Yes| REQ
 REQ --> DONE{Provider confirms?}
 DONE -->|Yes| CONFIRMED[Show confirmed booking and reminder options]
 DONE -->|No/timeout| COMP[Show pending/expired; release capacity and compensate payment]
 CONFIRMED --> RESCH[Reschedule: acquire new hold before changing current slot]
```

## Food order, taxi request, payment and tracking

```mermaid
sequenceDiagram
 participant U as User
 participant K as KUNDE
 participant M as Merchant/dispatch
 participant P as Payment provider
 U->>K: Build merchant cart / mobility request
 K->>M: Validate inventory or route estimate
 M-->>K: Current availability and quote
 K-->>U: Show itemized total, terms and expiry
 U->>K: Confirm exact request with idempotency key
 K->>P: Initiate payment when required
 P-->>K: Verified event or unknown result
 K->>K: Persist linked payment and order/task state
 K->>M: Submit fulfillment/dispatch request
 M-->>K: Accept, reject, assign or timeout
 K-->>U: Show confirmed state or recovery/refund pending
 U->>K: Track timeline; request support/cancel if eligible
```

Food uses merchant-specific cart and preparation/delivery states. Taxi uses pickup/destination, fare-estimate expiry and provider assignment; no restaurant cart. If provider rejects or cannot be found, show cancellation and verified payment-compensation status.

## Delivery, cancel, refund, rating

```mermaid
flowchart TD
 ACTIVE[Active order/booking] --> TRACK[Verified timeline; map only if live feed exists]
 TRACK --> DELAY{Late, unavailable or issue?}
 DELAY -->|No| COMPLETE[Completion verified]
 DELAY -->|Yes| OPTIONS[Show support, current ETA or eligible cancellation]
 OPTIONS --> CANCEL[Request cancellation with reason]
 CANCEL --> POLICY{Policy permits and user confirms consequence?}
 POLICY -->|No| KEEP[Keep current transaction; support route]
 POLICY -->|Yes| CSTATE[Persist cancellation request/state]
 CSTATE --> REF[Void/refund if applicable]
 REF --> RSTATE{Provider verifies refund?}
 RSTATE -->|Pending/failed| RP[Show refund pending and case status]
 RSTATE -->|Yes| RF[Show refunded/partial amount]
 COMPLETE --> RATE[Eligible rating and review]
 RF --> RATE
 RATE --> SUBMIT[Submit once; report/moderation route]
```

## AI search, comparison, booking and multi-step action

```mermaid
flowchart TD
 ASK[User asks in text or supported voice] --> INT[Resolve intent and permitted context]
 INT --> AMB{Ambiguous?}
 AMB -->|Yes| CLAR[Ask focused clarification]
 CLAR --> INT
 AMB -->|No| RET[Search via authorized tools]
 RET --> COMP[Present sourced options and compare basis]
 COMP --> PREP{Prepare action requested?}
 PREP -->|No| INFO[Answer with freshness and uncertainty]
 PREP -->|Yes| DRAFT[Create exact action draft and expiry]
 DRAFT --> REVIEW[Review provider, beneficiary, time, total, terms, data scope]
 REVIEW --> OK{Explicit confirmation for this draft?}
 OK -->|No| CANCEL[Cancel/save draft without commitment]
 OK -->|Yes| CHECK[Recheck permissions, price, availability and version]
 CHECK --> EXEC[Execute each action through domain API]
 EXEC --> PART{All task steps completed?}
 PART -->|Yes| SUCCESS[Show verified results and task history]
 PART -->|No| PARTIAL[Show completed, pending and failed steps separately]
```

Dentist + taxi + reminder is three dependent steps: appointment options first; book only after its confirmation; prepare taxi with a separate confirmation; schedule reminder only when opted in. If booking fails, do not schedule taxi. If taxi or reminder fails after booking succeeds, preserve the booking and explain the partial result.

## Flow coverage index

| Requested flow | Diagram/section |
|---|---|
| Registration, login, OTP, onboarding | Identity flow |
| Address selection, global search, category discovery, business/product selection | Discovery flow |
| Service booking, AI-assisted booking | Booking flow + AI flow |
| Food order, taxi order, payment, delivery tracking | Transaction sequence + delivery flow |
| Cancellation, refund, rating | Delivery flow |
| AI search, comparison, multi-step task | AI flow |

Every branch must preserve entered safe data, explain user options and emit auditable status. Payment/confirmation failures follow PRD 1.1 docs 09–17.
