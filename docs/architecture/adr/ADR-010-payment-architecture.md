# ADR-010: Payment Architecture

- **Status:** Proposed for review
- **Context/problem:** Payments span order/booking, delayed confirmation, refund, commission and settlement; provider not selected.
- **Options:** Direct provider-specific logic in domains; payment adapter plus immutable internal journal; wallet-first ledger.
- **Evaluation:** Direct coupling blocks replacement and consistent recovery. Adapter/journal centralizes idempotency/reconciliation while leaving regulated rails to provider. Wallet adds regulatory/accounting scope without MVP need.
- **Decision:** Recommend provider-neutral adapter, verified callbacks/status lookup, idempotent commands, append-only financial journal; no consumer wallet by default.
- **Consequences:** Payment and order state remain separate; refunds/settlement require explicit workflows and finance control.
- **Risks:** Provider semantics and Kazakhstan payment/legal requirements unknown; journal accounting model needs finance design.
- **Revisit when:** Selected acquirer contracts, capture/refund capabilities and regulatory model are confirmed.
