# 15 — Order, Booking and Payment Architecture

## Distinct aggregates

- **Order** owns cart/line/quote snapshots, fulfillment mode, merchant decisions and order state.
- **Booking** owns service/resource/time slot, hold, beneficiary, confirmation/reschedule and appointment lifecycle.
- **Payment** owns provider attempt, authorization/capture/void/refund/dispute references and immutable financial journal.
- **Pricing** owns quote calculation/version and promotion eligibility. A quote snapshot is copied into transaction for later audit.

They link through opaque IDs, never share one mutable “transaction status”. Category workflows compose them through a coordinator and compensating actions, not distributed ACID.

## Order flow and recovery

1. Client obtains current quote/cart version; server revalidates catalog/stock/address/area/policy.
2. Persist order intent + payment attempt idempotency reference; call payment adapter outside DB transaction.
3. Verify authorization/capture by signed callback and/or status query; keep unknown as pending.
4. Persist provider fact and order transition; submit merchant fulfillment using outbox and idempotent request ID.
5. Merchant acceptance/rejection and delivery events advance state machine from PRD 1.1 §09.
6. Rejection/timeout releases inventory and voids authorization or refunds captured amount; user sees compensation pending until provider confirms.

Payment succeeds but order persistence fails: correlated retry to persist intent; if irrecoverable, compensation workflow, exception queue and user notice. Never silently discard payment or ask user to pay again while state is unknown.

## Booking/slot integrity

Availability is provider/resource-specific. Create short-lived hold via atomic constraint/transaction; hold expiry is explicit. Payment callback after hold expiry cannot force confirmation: search alternatives and compensate. Reschedule creates replacement hold; preserve old slot until replacement confirms where feasible. Use optimistic version and unique conflict constraint to stop double-booking. Confirmed booking does not mean payment captured unless payment status independently confirms it.

## Saga and idempotency

Coordinator records workflow ID, step, attempt, deadline, external reference and compensation status. Each command has unique idempotency key; provider callback event IDs deduplicated. Retry only known retryable operation with same logical key. Compensation itself has separate idempotency and remains visible if pending/failed. Terminal states are not reopened; correction uses compensating event/record.

## Financial journal

Append-only entries represent authorization, capture, fee/commission accrual, settlement, refund, chargeback and adjustment. Integer minor units/currency; double-entry structure recommended once accounting/finance model is validated. Partner settlement is separate from customer charge and requires KYC/contract/tax sign-off. No invented commission formula.

## Cancellation/dispute

Policy is versioned by category and provider contract. Evaluate actor, state, elapsed time, fulfilled portion and law; show outcome estimate before user confirms. A disputed completion/charge preserves original timeline and routes to support/finance. See PRD 1.1 docs 09–12.
