# 07 — Domain Boundaries and Data Ownership

All domains are initially modules, not separately deployed services. “Inbound/outbound” denotes module contract/event responsibilities. Security: all records tenant-scoped where applicable, purpose-limited and audited for privileged access. Extraction triggers are in 29.

| Domain / owner | Responsibility, core entities and operations | Inbound / outbound events and dependencies | Scale / extraction trigger |
|---|---|---|---|
| Identity & Access / IAM | Account, credential reference, session, device, role grant; verify, authenticate, revoke, authorize | Auth APIs; `UserRegistered`, `AccessGrantChanged`; no dependency on marketplace | High auth load, independent security boundary |
| User & Family / User | Profile, Address, Family, Membership, Consent; manage own/shared data | User APIs; `AddressChanged`, `FamilyGrantChanged`; IAM | PII isolation or team ownership |
| Partner / Partner | Business, location, verification, employee and scoped role | Onboarding APIs; `PartnerRegistered`, `PartnerStatusChanged`; IAM, catalog | Partner scale/verification workflow separation |
| Provider / Provider | Provider profile, eligibility, availability, assignment reference | Provider/assignment APIs; `ProviderAssigned`, `ProviderAvailabilityChanged`; IAM, dispatch | Driver workload/location stream |
| Marketplace/Catalog / Catalog | Category, listing, service/product, versions, publication, inventory reference | Discovery APIs; `CatalogPublished`, `ListingSuspended`; Partner | Catalog scale/editorial independent deployment |
| Location / Geo | Address reference, service area, coordinate precision, route/geo-provider references | Geocode/serviceability APIs; `ServiceAreaChanged`; User, Catalog | Geo throughput/provider adapter need |
| Pricing/Promotions / Pricing | Quote snapshots, fee/discount eligibility, policy version | Quote APIs; `QuoteExpired`, `PromotionApplied`; Catalog, Geo | Independent rule evaluation/traffic |
| Search / Search | Query, filters, ranking and denormalized listing projection; never owns source listing | Search API; consumes catalog/location events | Likely first read-heavy extracted projection |
| Orders / Order | Order/cart snapshot, lines, fulfillment lifecycle and state transitions | Order APIs; `OrderCreated/Accepted/Cancelled`, `DeliveryCompleted`; Pricing, Catalog, Payments | Transaction volume/team/failure isolation |
| Bookings / Booking | Reservation, slot hold, resource/capacity, reschedule lifecycle | Booking APIs; `BookingCreated/Confirmed/Cancelled`; Catalog, Pricing, Payments | Contention/independent capacity scaling |
| Mobility / Mobility | Trip request, quote, dispatch state and trip events | Mobility APIs; `ProviderAssigned`, trip updates; Geo, Provider, Payments | Location stream/dispatch latency needs |
| Delivery / Delivery | Delivery task, pickup/dropoff, proof and exception; separate from order | Delivery APIs/events; Order, Provider, Geo | High-frequency tracking/partner integration |
| Payments/Ledger / Finance | Payment attempt, provider ref, journal, refund, dispute, reconciliation, settlement | Payment commands; `PaymentConfirmed/Failed`, `RefundRequested/Completed`; Order/Booking via IDs only | Strong candidate for isolated access/ops boundary; regulated controls |
| Reviews / Trust | Review eligibility, rating, report, moderation action | Review API; `ReviewCreated`; Order, IAM | Moderation volume/independent policy |
| Loyalty / Growth | Points, entitlement and campaign claims; deferred | Promotion interface; loyalty events | Later, when approved economic model exists |
| Notifications / Messaging | Durable outbox delivery state and preferences | Event consumers; delivery results; IAM, transaction IDs | High fanout or channel reliability |
| Support / Support | Case, messages, evidence references, resolutions | Case APIs; `SupportCaseOpened/Resolved`; role-scoped reads | Case volume/support tooling separation |
| AI Orchestration / AI | Conversation, task plan, step, draft, confirmation ref, tool result/cost metadata | AI APIs; `AITaskStepCompleted`; calls approved domain ports | Independent model latency/cost/security controls |
| Analytics / Data | Minimized event schema, aggregation and metrics | Event consumer; product/ops dashboards | Data volume/BI isolation; keep out of write path |

## Dependency constraints

Orders must not own catalog inventory; they capture a quote/catalog snapshot and request inventory reservation through contract. Payments own payment/journal records; orders/booking keep status references only. Search owns a projection, not canonical listing details. AI owns task state, not underlying user/order/payment state. Analytics has no write authority over operational aggregates. Circular dependencies are prohibited; shared kernel is limited to stable primitives (IDs, money, time, locale, correlation) with versioned contracts.
