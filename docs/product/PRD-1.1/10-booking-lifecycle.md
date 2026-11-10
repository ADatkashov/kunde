# 10 — Booking Lifecycle

Booking reserves a time, capacity or resource for a person/service. It is distinct from an order even when tied to a fee, ticket or service package.

```mermaid
stateDiagram-v2
 [*] --> DRAFT
 DRAFT --> PENDING_CONFIRMATION: request submitted
 PENDING_CONFIRMATION --> PENDING_PAYMENT: payment required
 PENDING_CONFIRMATION --> CONFIRMED: provider confirms/no payment required
 PENDING_CONFIRMATION --> EXPIRED: response deadline/slot hold expires
 PENDING_PAYMENT --> CONFIRMED: verified payment and slot valid
 PENDING_PAYMENT --> EXPIRED: hold/payment deadline expires
 CONFIRMED --> RESCHEDULE_REQUESTED
 RESCHEDULE_REQUESTED --> RESCHEDULED: replacement slot confirmed
 RESCHEDULE_REQUESTED --> CONFIRMED: rejected/abandoned; old slot retained
 CONFIRMED --> CHECKED_IN --> IN_PROGRESS --> COMPLETED
 CONFIRMED --> NO_SHOW
 CONFIRMED --> CANCELLATION_REQUESTED
 RESCHEDULE_REQUESTED --> CANCELLATION_REQUESTED
 CANCELLATION_REQUESTED --> CANCELLED
 CANCELLED --> REFUND_PENDING --> REFUNDED
 COMPLETED --> DISPUTED
 NO_SHOW --> DISPUTED
```

## Availability and transition rules

- Slot inventory is keyed by service, location, staff/resource, duration and time zone. Overlapping resources are checked atomically.
- Hold has configured expiry shown to user. Expired holds release capacity. A successful payment confirmation after hold expiry is reconciled: do not confirm unavailable slot; offer alternatives and compensate payment.
- `PENDING_CONFIRMATION` is used only if provider approval is required. Direct confirmation requires the same atomic capacity reservation.
- `PENDING_PAYMENT` is used only when policy requires payment/deposit. `CONFIRMED` requires all mandatory approval and payment conditions verified.
- Reschedule obtains a new hold. Keep old booking/slot until the new slot is confirmed when capacity/provider rules allow; otherwise disclose the temporary policy clearly.
- Cancellation deadline, fee and no-show policy are shown at confirmation. Values are category/provider contract configuration, not global assumptions.
- Check-in and completion evidence is category-dependent. No-show requires disclosed grace period and event evidence; it is not inferred solely from missed app interaction.
- Provider rejection/timeout expires or cancels request, releases inventory, initiates applicable payment compensation and notifies consumer.

Invalid transitions (e.g. check-in before confirmation, completion after cancellation, confirming expired slot) are rejected. Every transition records actor, old/new state, slot/resource and policy version.
