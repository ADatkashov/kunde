# 11 — Customer Support Operations

## Channels and case model

In-app ticket linked to order/booking/payment is the durable source of truth; live chat may be added when staffed. Email/phone channels require verified routing and case capture. Emergency/safety concern gets an explicit urgent path and local emergency guidance; KUNDE must not imply a staffed emergency service unless it exists. Partner/provider support queues are separate from consumer queue with scoped shared case context.

Case fields: case ID, requester/role, transaction ID, category/reason code, priority, customer-visible summary, restricted evidence refs, assigned queue/owner, state, due timers, linked payment/refund, partner/provider response, decision/reason, appeal link and audit. Do not copy full transaction/health data into free-text notes unnecessarily.

## Categories and priority

| Priority | Examples | Proposed pilot first-response target (hypothesis) | Escalation |
|---|---|---|---|
| P0 Critical | Safety threat, suspected active fraud/account takeover, broad payment integrity incident | Immediate on-call alert; human acknowledgement target ≤5 min only if staffed | Operations lead + security/finance/legal as applicable |
| P1 Urgent | Payment charged/order missing, active delivery failure, provider no-show now | Acknowledge ≤15 min during published support hours | Transaction operations; finance/payment owner |
| P2 Standard | Refund status, wrong/missing item, booking change, partner complaint | Acknowledge ≤4 business hours | Category support lead |
| P3 General | How-to, profile/settings, suggestions | Acknowledge ≤1 business day | General support queue |

These are **proposed service design targets, not current service promises**. Confirm staff coverage, channels, provider obligations and law before publication. Response time differs from resolution time; show honest status and updates.

## Resolution and escalation

Agent verifies requester scope and transaction state; gathers only needed evidence; explains verified fact vs unknown; offers policy-supported options; creates financial action request if authorized; never edits ledger. Escalate money mismatch to Finance, safety/abuse to Trust/Security, health/child concern to trained specialist, partner conduct to Operations, legal threat/regulatory notice to Compliance/Legal. Cases can be reopened as a linked continuation; preserve original record.

## AI-assisted support

AI can classify, retrieve authorized transaction facts, draft a response and summarize a case. Agent reviews before sending when content is disputed, sensitive or consequential. AI cannot promise refund, determine liability, suspend a party, waive contract, make medical/legal claims or move money. Every suggestion records model/tool metadata, reviewer, edit and final decision without unnecessary conversation retention.

## Quality metrics

First-response time, resolution time by reason, reopen rate, customer satisfaction after resolution, transfer rate, refund outcome, aged backlog, escalation accuracy, contact rate per completed transaction and privacy/access incidents. Track by category and severity; do not optimize average by ignoring unresolved P0 cases.
