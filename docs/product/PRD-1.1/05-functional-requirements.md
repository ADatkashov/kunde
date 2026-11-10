# 05 — Functional Requirements

Normative requirements are categorized by domain. Priority and phase: see document 21. “Candidate P0” is gated by live operations; support for a category in the data model is not launch approval.

## Identity and profile

| ID | Requirement | Priority / phase | Source |
|---|---|---|---|
| AUTH-001 | Phone registration must verify a one-time challenge before account activation; challenge expiry, resend limits and generic account responses prevent replay and enumeration. Authentication channel is provider-abstracted. | P0 / 0–1 | PRD 1.0 §6.1 |
| AUTH-002 | Login, logout, recovery and session revocation must bind sessions to account/device metadata, expire them by policy and require fresh authentication for sensitive actions. | P0 / 0–1 | §6.1 |
| USER-001 | User may view/update allowed profile fields and locale; changed contact details require reverification. | P0 / 1 | §4.5, §6.1 |
| USER-002 | User may create, edit, delete and select addresses; address ownership and sharing are explicit. Location permission denial has manual-address path. | P0 / 1 | §4.1, §6.2 |
| USER-003 | User controls favorites and optional marketing preferences; mandatory service/security messages remain deliverable. | P1 / 1–2 | §4.5, §6.5 |
| USER-004 | Consent, privacy access/export and account-deletion requests are recorded and processed under approved retention policy; deletion status is visible. | P1 / 1–2 | §15 |
| FAM-001 | Family owner can invite, scope, suspend and revoke members; each member has an independent identity and privacy settings. | P2 / 3 | §2.2, §4.5 |
| FAM-002 | Booking or ordering for another member requires explicit guardian/delegation authority and records the acting user separately from beneficiary. | P2 / 3 | §2.2, §15 |

## Home, explore and search

| ID | Requirement | Priority / phase | Source |
|---|---|---|---|
| HOME-001 | Home must allow explicit location selection and show which location scopes results. | P0 / 1 | §4.1 |
| HOME-002 | Home must render supported categories, search and activity entry points; unsupported/inactive categories must not appear as orderable. | P0 / 1 | §4.1, §11 |
| HOME-003 | Recommendations/popular/nearby modules must be eligible for selected location and disclose empty/loading/error states. | P1 / 1–2 | §4.1 |
| HOME-004 | Promotion display must include material eligibility, validity and price terms; expired offers cannot be applied. | P2 / 2 | §4.1 |
| SEARCH-001 | Search covers category/business/product/service with explicit category facets, location, availability, price/rating filters and stable sorting. | P0 / 1 | §4.2, §6.2 |
| SEARCH-002 | Results expose freshness and availability; unavailable listings cannot proceed to checkout/booking without refresh. | P0 / 1 | §6.2 |
| SEARCH-003 | Empty, partial, timed-out and permission-denied search states preserve query and allow recovery without fabricated results. | P0 / 1 | §4.2 |
| EXP-001 | Details must show identity, category, location/service area, price model, availability, rules, rating provenance and support route. | P0 / 1 | §4.2 |

## Category transaction requirements

### Category operational profiles

Shared platform functions (identity, discovery, support, notifications, payment abstraction and audit) are reused, but transaction shape remains category-specific. Every provider profile must include verified business/provider identity as required, service area/location, hours, support/escalation route, cancellation terms, current status and localized customer-facing information. Required provider evidence depends on category and legal review.

| Category | Catalog and provider attributes | Price and availability | Location, discovery and transaction | Payment, cancellation, communication, rating and support |
|---|---|---|---|---|
| Mobility | Vehicle/service class, capacity, accessibility/cargo attributes where offered; driver eligibility and vehicle data per operating model | Fare estimate with basis and expiry; dispatch availability is live/approximate and must not promise assignment | Pickup/destination, route and time; select service class, confirm request, dispatch, assignment, trip progress, completion | Disclose estimate/fare rules; capture timing follows provider capability/policy. Cancellation depends on dispatch/trip state. Controlled trip communication, post-trip rating, safety/incident support. |
| Food & Shopping | Merchant location, menu/products, options/modifiers, ingredients/allergens where verified, stock, substitutions and fulfillment modes | Item price, quantity, fees and delivery/pickup availability; revalidate at checkout and acceptance | Merchant-scoped search and cart; delivery address or pickup; order, merchant acceptance, preparation and handoff | Payment linked to order; refunds can be line-level for missing/incorrect items under approved policy. Substitution consent, delivery updates, rating after eligible completion, support case. |
| Home | Service scope, inclusions/exclusions, skill/credential evidence, equipment/material responsibility, service duration | Fixed price, estimate or quote explicitly labeled; schedule/capacity and travel area; no work before final quote acceptance when required | Address, access instructions and optional photos collected only as necessary; discover, request, assess/quote, accept, schedule, fulfill | Deposit/payment timing by validated policy; cancellation and call-out terms disclosed. Controlled provider contact, completion evidence, quality dispute workflow and review. |
| Health | Provider/practitioner credentials, specialty, clinic location, visit mode, service description; regulated data only after compliance approval | Appointment fee/coverage representation only when verified; staff/room/slot availability | Search by specialty/location/time; select practitioner/slot and book; health services/pharmacy disabled until legal review | Sensitive payment/health handling; cancellation/no-show terms; secure minimum necessary communication, no public health details in review, clinical support/escalation boundaries. AI never diagnoses. |
| Personal Care | Service, duration, price, staff skills/profile, location, equipment/resource requirements | Staff/resource-specific slots; capacity held atomically; optional deposit only if disclosed | Location/staff/time filters; select service and employee, reserve slot, check in and complete | Payment/deposit per approved provider policy; reschedule/cancel by disclosed deadline. Appointment reminders, limited provider messaging, eligible review and service complaint support. |
| Family & Education | Course/class, age/eligibility, curriculum/activity, instructor credentials, capacity, schedule and safeguarding information | Per-session/course pricing, term and capacity; age and schedule constraints validated | Location, age band and schedule search; guardian-authorized enrollment or booking; attendance and reminders | Guardian approval and payer/beneficiary separated. Cancellation/refund per enrollment terms; child contact data minimized, guardian-mediated communication, safeguarding escalation, moderated reviews. |
| Experiences | Event/venue, date/time, ticket type, seat/quantity, entry conditions, accessibility and organizer identity | Inventory/seat availability with hold expiry; ticket price/fees and event status revalidated | Search by location/date/category; select event/tickets, reserve/confirm, issue ticket, validate admission | Payment success does not prove ticket issuance; issuance failure triggers compensation. Cancellation/refund follows organizer/legal rules. Ticket support, admission incident case, post-event review where eligible. |
| Auto | Service type, vehicle compatibility, parts/material scope, facility/provider credentials, estimated duration | Fixed, estimate or inspection-required quote; bay/technician/dispatch availability | Vehicle profile is optional and consented; filter by location/compatibility, select service and appointment or roadside dispatch | Additional work/price requires customer approval. Cancellation/call-out policy disclosed. Controlled provider contact, evidence for disputed work, support and rating after completion. |

Cross-category invariants: listing and quote freshness are visible; no workflow exposes a provider as available without current operational evidence; a consumer can reach support from a transaction; ratings are tied to eligible completed transactions; sensitive data stays out of public catalog and general analytics. A category-specific policy must override shared defaults explicitly and carry a version.

| ID | Requirement | Category behavior | Priority / phase | Source |
|---|---|---|---|---|
| FOOD-001 | Cart is merchant-scoped; item options/modifiers, quantity, availability and price are validated at checkout; merchant minimums/fees shown before confirmation. | Food & shopping | P0 candidate / 1 | §5.2, §6.3 |
| FOOD-002 | Fulfillment choice (delivery/pickup where actually offered), address, instructions and substitutions (if supported) are explicit and auditable. | Food & shopping | P0 candidate / 1 | §5.2 |
| MOB-001 | Request captures pickup, destination, service type, estimate and estimate expiry; provider dispatch and assignment are explicit states. | Mobility | P0 candidate / 1 | §5.1 |
| HOME-005 | Quote-based home services distinguish estimate from final quote; provider work does not begin until price/scope is accepted. | Home | P2 / 2 | §5.3 |
| HEALTH-001 | Provider discovery/booking may show credentials and appointment data; health information is sensitive and AI cannot diagnose. Regulated transactions remain disabled pending review. | Health | P3 / 3 | §5.4, §15 |
| CARE-001 | Appointment selection captures service, duration, optional staff/resource and valid slot; provider confirmation and cancellation terms are shown. | Personal care | P2 / 2 | §5.5 |
| FAMILY-003 | Enrollment/booking for dependent requires guardian authority, capacity and schedule details; only necessary child data is shared. | Family & education | P2 / 3 | §5.6 |
| EVENT-001 | Ticket inventory, event/time, quantity, admission credential and cancellation rules are checked before commitment; ticket transfer/resale is not assumed. | Experiences | P2 / 3 | §5.7 |
| AUTO-001 | Service selection supports vehicle profile only with user consent, estimate/inspection distinction and appointment/dispatch rules. | Auto | P2 / 2 | §5.8 |

## Transactions, support and operational roles

| ID | Requirement | Priority / phase | Source |
|---|---|---|---|
| ORDER-001 | Order draft captures immutable line/quote snapshots and validates availability, address, total and policy before payment. | P0 candidate / 1 | §6.3 |
| ORDER-002 | Order placement is idempotent and linked to verified payment state; client timeout is resolved by lookup before retry. | P0 candidate / 1 | §6.3, §13 |
| ORDER-003 | Customer and fulfillment actors see role-appropriate state timeline; every transition is server-validated and audited. | P0 candidate / 1 | §6.3 |
| BOOK-001 | Booking uses expiring slot hold and atomic conflict prevention across staff/resources; hold expiry frees slot. | P1 / 2 | §5 categories |
| BOOK-002 | Reschedule/cancel follows disclosed, versioned policy; old slot remains until replacement confirms where feasible. | P1 / 2 | §5 categories |
| PAY-001 | Payment initiation/authorization/capture/refund is represented separately from order/booking and changes only from verified provider events or audited reconciliation. | P0 candidate / 1 | §6.4 |
| PAY-002 | Every money-moving command has idempotency, immutable ledger reference, currency/amount validation and reconciliation state. | P0 candidate / 1 | §6.4, §13 |
| ACT-001 | Activity lists active and past order, booking, payment/refund and case references with status filters. | P0 / 1 | §4.4 |
| SUP-001 | User can submit a case linked to a transaction and attach permitted evidence; case visibility is scoped to parties and assigned support. | P0 candidate / 1 | §4.5, §10 |
| PARTNER-001 | Verified business roles can maintain scoped profile, catalog and service hours; unverified supply is non-orderable. | P0 candidate / 1 | §8 |
| PARTNER-002 | Partner staff can accept/reject/update only assigned or authorized business requests before timeout and within legal transitions. | P0 candidate / 1 | §8 |
| PROVIDER-001 | Driver/courier/provider sees and updates only assigned work; assignment data is minimized and expires when no longer needed. | P0 candidate / 1 | §9 |
| OPS-001 | Support can locate authorized case/transaction, record reason/evidence and issue only granted actions; all access and overrides audited. | P0 candidate / 1 | §10 |
| OPS-002 | Moderator can review reported content, apply policy outcomes and record appeal path without finance privilege. | P1 / 1–2 | §10 |
| FIN-001 | Finance can reconcile verified provider events against immutable platform transactions and flag mismatches for review. | P0 candidate / 1 | §10, §13 |
| ADMIN-001 | Admin role grants and configuration are least-privilege, scoped, reviewable and audited; break-glass elevation is time-bounded. | P0 / 0–1 | §10, §13 |

## AI

| ID | Requirement | Priority / phase | Source |
|---|---|---|---|
| AI-001 | AI can answer discovery/help requests using only authorized platform retrieval and must distinguish facts, estimates and recommendations. | P1 / 1 | §7 |
| AI-002 | AI may prepare multi-step order/booking drafts but must display items, provider, location, total, terms, expiry and affected account before execution. | P1 / 4 | §7 |
| AI-003 | Paid or otherwise consequential action requires explicit, version-bound user confirmation, then renewed permission and availability checks. | P1 / 4 | §7.3 |
| AI-004 | AI tools cannot write payment ledger, bypass state machines, grant permissions, expose other family data or suppress audit records. | P0 / 0 | §7.3–7.4 |
| AI-005 | User can inspect/delete retained conversation context; transaction audit records follow separate retention rules. | P2 / 4 | §7.4, §15 |

