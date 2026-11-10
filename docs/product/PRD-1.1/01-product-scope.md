# 01 — Product Scope

## Purpose

Turn KUNDE PRD 1.0 into functional contracts without changing its vision: one consumer account and discovery experience for everyday services, launched in phases with AI as a permission-aware assistant. The initial market is Almaty, Kazakhstan; launch supply and integrations are not yet confirmed.

## Product surfaces

| Surface | 1.1 scope | Later scope |
|---|---|---|
| Consumer app | Identity/profile, location, search, real supported catalog, one or more operational categories, order/booking activity, support, basic AI-assisted discovery | Family coordination, cross-category plans, richer personalization |
| Partner interface | Minimum onboarding, catalog/availability and request processing for selected MVP supply | Settlements, staff, analytics, multi-location operations |
| Driver/provider interface | Only if the selected fulfillment model needs it; assignment and status flow | Earnings, route optimization, broader provider tools |
| Admin portal | Support, moderation, transaction lookup, cancellation/refund escalation, audit | Full fraud, analytics, policy and operations suite |

## Launch principle

P0 describes foundation and a narrow Almaty pilot. Food ordering is the candidate transactional category because PRD 1.0 proposes it, but actual public launch is conditional on signed supply, delivery/fulfillment, payment, support, refund and legal readiness. Grocery, mobility/courier, and every other category stay conditional until their operation is evidenced. Do not advertise a category as available merely because a screen or catalog taxonomy exists.

## In scope for this specification

- Consumer, family, partner, provider and platform roles.
- Discovery and category-specific transaction paths.
- Separate order, booking and payment state machines.
- Failure, retry, cancellation, refund, dispute and notification behavior.
- AI retrieval, preparation and confirmed execution boundaries.
- Screen and API-level functional contracts, analytics, localization and acceptance criteria.

## Out of scope for PRD 1.1

- Visual design, architecture choices, implementation, vendor selection, detailed database schema, legal advice, medical advice, financial products, autonomous payments, international launch, and guaranteed availability of third-party integrations.

## Recommendation / requirement baseline

This document may clarify behavior implicit in PRD 1.0, but adds recommendations where it lacks detail. Recommendations are not represented as already approved business policy. Product owner validation is required for pricing/commission, cancellation windows, refund eligibility, verification, retention, and category launch selection.

## Release gates

1. Supply can accept and fulfill the supported transaction end to end.
2. Payment authorization/capture and reconciliation are verified with the selected provider.
3. Support can inspect and resolve failed, duplicate, cancelled and disputed transactions.
4. Privacy, security, legal and operational review passes for each enabled category.
5. Analytics distinguish requested, accepted, fulfilled, cancelled and refunded outcomes.

Related: `21-mvp-release-priorities.md`, `23-assumptions-and-open-decisions.md`.
