# ADR-008: AI Provider Abstraction

- **Status:** Proposed for review
- **Context/problem:** AI is cross-category and provider must be replaceable while respecting data residency and explicit user authorization.
- **Options:** One provider SDK in domains; provider-neutral model gateway and typed tools; self-hosted models.
- **Evaluation:** Direct SDK coupling is simple initially but spreads vendor-specific semantics and prompt/data exposure. Gateway controls routing, budget and policy but adds an internal component. Self-hosting offers control but increases compute/ML operations and may not meet quality/cost.
- **Decision:** Provider-neutral gateway, no provider selection until data-processing region/terms and quality are assessed; all tool calls via allowlist and domain APIs.
- **Consequences:** Model output is untrusted; no direct DB/payment access; require cost, audit, confirmation and evaluation harness.
- **Risks:** External model processing may conflict with jurisdiction/privacy requirements; abstraction may not erase provider-specific behavior.
- **Revisit when:** Approved data flows and measured quality/cost justify provider routing or self-hosting.
