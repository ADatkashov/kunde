# 31 — Requirements Traceability

This matrix maps the complete PRD 1.1 functional requirement set (46 unique IDs) to implementation boundaries; platform/NFR requirements in PRD 1.1 §22 are linked by topic below. Architecture implementation tickets must retain these IDs.

| Requirement | Source | Component / API or event | Data owner | Security implication | Test implication |
|---|---|---|---|---|---|
| AUTH-001/002 | PRD 1.1 §§05,07 | IAM; `/auth/challenges`, `/auth/sessions` | IAM | OTP/session secrets, rate limits, enumeration | Expiry/replay/rotation/revocation |
| USER-002 | §05 | User/Geo; `/me/addresses` | User/Geo | Precise location classification | Permission denied, service-area rejection |
| USER-001/003/004 | §05, §18, §26 | User/Privacy APIs; consent/deletion events | User and each source domain | Consent, retention, marketing preference | Contact reverification, withdrawal, deletion propagation |
| FAM-001/002 | §05, §13 | Family membership/grant API; `FamilyGrantChanged` | User/Family | Explicit member/guardian scope | Revocation and cross-member denial |
| HOME-001–004 | §05, §08, §15 | Home APIs; category, location and promotion queries | Location, Catalog, Pricing | Location permission; promotion eligibility | No location, unavailable category, expired offer |
| SEARCH-001/002 | §05, §15 | Search; `/search`; `CatalogPublished` | Catalog owns source, Search projection | Coarse geo, no sensitive query logging | Stale index vs canonical revalidation |
| SEARCH-003, EXP-001 | §05, §15 | Search and catalog detail APIs | Catalog/Search | Result-level authorization, query minimization | Empty/partial/error search, unavailable listing |
| HOME-005 | §05 | Catalog/Quote; service quote API | Pricing and Catalog | Scope/price disclosure | Estimate vs accepted final quote |
| FOOD-001/002, ORDER-001/002/003 | §05, §09 | Catalog/Pricing/Order; `/carts`, `/orders`; `OrderCreated/Accepted/Cancelled` | Order + Catalog | Tenant scope, immutable quote | Duplicate key, stock/price change, partner rejection |
| MOB-001, PROVIDER-001 | §05, §09 | Mobility/Provider; request/assignment API; `ProviderAssigned` | Mobility/Provider | Location/contact minimization | No-provider timeout, reassignment, revoked provider |
| HEALTH-001 | §05, §16, §26 | Catalog/Booking/AI disabled until review | Health-sensitive domain owner TBD | Sensitive/regulated data boundary | Launch configuration blocks unapproved service |
| CARE-001, FAMILY-003, EVENT-001, AUTO-001 | §05, §10 | Category-specific service/booking/ticket/vehicle contracts | Catalog, Booking, Event inventory, Auto service | Dependent, ticket and vehicle data | Resource collision, ticket failure, changed quote |
| BOOK-001/002, CARE-001 | §05, §10 | Booking; `/slot-holds`, `/bookings`; `BookingConfirmed/Cancelled` | Booking | Beneficiary, resource authorization | Concurrent hold, expiry, reschedule failure |
| PAY-001/002, FIN-001 | §05, §11 | Finance; payment/refund API/webhooks; `PaymentConfirmed`, `RefundCompleted` | Finance | PCI scope minimization, immutable financial data | Delayed/replayed callback, orphan order, reconciliation |
| FAM-001/002, FAMILY-003 | §05, §13 | User/Family; family APIs; `FamilyGrantChanged` | User | Guardian, consent, child data isolation | Revocation and cross-member denial |
| ACT-001, SUP-001 | §05, §08 | Activity and case APIs; `SupportCaseOpened/Resolved` | Order, Booking, Finance, Support | Case-scoped access, transaction privacy | Pagination, duplicate case, unauthorized case read |
| AI-001–005 | §05, §16 | AI gateway/tool registry; task/confirmation APIs | AI owns task; domain owns effects | Prompt injection, privilege boundary, retention | Draft tampering, unauthorized tool, partial execution |
| PARTNER-001/002 | §05, §09 | Partner/Catalog; onboarding and request commands | Partner | Tenant isolation and privileged grants | Suspended business and unauthorized employee |
| OPS-001/002, ADMIN-001 | §05, §10, §13 | Admin/support/moderation; case and audit API | Support/Platform | Purpose-bound access, separation of duties | Audit completeness, role separation |
| USER-004, AI-005 | §05, §16, §26 | Privacy workflow; deletion/export API | Each domain owns purge | Retention/legal hold and processor inventory | Deletion propagation/retained records |

Full unique ID-to-AC and release mapping: `../product/PRD-1.1/24-requirements-traceability.md`. Additional NFR trace map: security → 18/26/27; reliability/performance → 19/21–23/27; i18n → 25; observability → 21; residency → 19/26; cost → 28.
