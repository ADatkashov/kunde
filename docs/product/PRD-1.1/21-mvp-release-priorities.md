# 21 — MVP Priorities and Release Phases

**Priority:** P0 launch-critical foundation/selected category; P1 early growth; P2 later; P3 long-term/regulatory or advanced vision. **Phase:** 0–6 as PRD 1.0 defines. Category readiness is a separate gate from priority.

| Capability | Priority | Phase | Launch condition |
|---|---|---|---|
| Identity, sessions, profile, consent, scoped address | P0 | 0–1 | Security/privacy review; OTP provider selected |
| Home, supported categories, unified search, listing detail | P0 | 0–1 | Real eligible inventory; freshness and empty states |
| Selected food order flow: catalog/cart/quote/partner acceptance/status | P0 | 1 | Merchant supply, fulfillment, support, cancellation and refund operations proven |
| Payment attempt, verified status, idempotency, compensation/reconciliation | P0 | 0–1 | Selected payment partner and finance runbook verified |
| Activity, receipts/status, support and basic admin operations | P0 | 1 | Staffed support, permission model, incident monitoring |
| Partner onboarding/catalog/request processing | P0 for selected category | 1 | Verification, response SLA and operational owner |
| Driver/courier interface | Conditional P0 | 1 | Only if chosen delivery model requires first-party provider workflow |
| Grocery | P1 | 1/2 | Inventory freshness, substitutions and merchant operations ready |
| Mobility/courier | P1 | 1/2 | Dispatch integration, estimates, safety, availability and incident ops ready |
| Basic AI search/help/recommendations | P1 | 1 | Reliable search API, source/freshness labels, privacy and fallback |
| Ratings, favorites, marketing promotions | P1/P2 | 1/2 | Abuse/moderation and consent controls |
| Home, personal care, auto bookings | P2 | 2 | Category-specific provider capacity, quote/slot/refund policies |
| Family/education, health, experiences | P2/P3 | 3 | Guardian/privacy/regulatory/ticket inventory requirements complete |
| Multi-step AI planning/execution, proactive assistance | P3 | 4 | Permission, confirmation, audit, compensation and monitoring gates |
| Kazakhstan city expansion | P2 | 5 | Local supply, support, localization, service areas and economics validated |
| International expansion | P3 | 6 | Local regulation, payments, language and partner operations validated |

## Phase gates

- **Phase 0 Foundation:** identity/security model, domain contracts, location/search foundation, AI provider abstraction and operational policy defined.
- **Phase 1 Almaty MVP:** only selected high-frequency categories with complete real transaction support; no category placeholders that appear orderable.
- **Phase 2 Everyday Services:** home, personal care, auto and advanced booking after quote/availability operations exist.
- **Phase 3 Family & Lifestyle:** family, education, health and experiences after special privacy and regulated-service reviews.
- **Phase 4 AI Life Assistant:** task orchestration and authorized execution only after explicit confirmation and tool controls pass.
- **Phase 5 Kazakhstan Expansion / Phase 6 International:** city/country readiness assessed separately; no assumption that Almaty policy generalizes.

No MVP feature is accepted solely because it appears in an app. Each must meet supply, payment, support, monitoring, privacy and incident response gates in document 01.
