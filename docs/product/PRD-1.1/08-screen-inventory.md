# 08 — Screen Inventory

Screen IDs are stable. Every screen must support accessible labels, focus order, dynamic text, loading/empty/error states appropriate to its data, and localized copy. Offline mode is read-only unless a specifically approved queueing policy exists.

## Consumer app

| ID / screen | Roles, entry, components/actions | Data, states, permission, phase |
|---|---|---|
| C-01 Home | Consumer; app start/tab. Location, search, category shortcuts, recommendations, active orders/bookings, AI entry. Select location/category/transaction. | Catalog, location, activity; skeleton/empty/retry; location optional/manual path; P0/1 |
| C-02 Explore/Search | Consumer/guest; Home or tab. Query, category, filters, sort, result cards, recent queries. | Search API, location; no result/offline/partial; location access optional; P0/1 |
| C-03 Business/Service/Product detail | Consumer; result. Price model, hours, service area, availability, terms, rating, menu/catalog, support. | Listing freshness and policy; unavailable state; P0/1 per enabled category |
| C-04 Cart/Checkout | Consumer; item detail/cart. Lines/options, address, fulfillment, quote, discount, terms, payment selection, confirm. | Live stock/quote; stale/error states; auth/payment consent; P0 candidate/1 |
| C-05 Mobility request | Consumer; Mobility. Pickup/destination, map/manual input, tier, estimate expiry, confirm. | Route/dispatch quote; denied location/manual path; P0 candidate/1 |
| C-06 Slot selection/Booking review | Consumer; service details. Date, staff/resource, slot, hold timer, price, terms, confirm/reschedule. | Live slot/hold; collision/expired states; P1/2 |
| C-07 AI conversation | Consumer; AI tab, Home or detail. Messages, suggestions, source/options, draft review, confirm/cancel, task status. | Conversation/tool status; uncertainty/failure/partial states; consent and action-specific auth; P1/1 retrieval, P1/4 execution |
| C-08 Activity list/detail | Consumer; tab/notification. Orders, bookings, payment/refund references, timeline, receipt, cancel, support. | Own transactions; loading/empty/pending; auth; P0/1 |
| C-09 Support case | Consumer; transaction/help. Issue type, description/evidence, status and reply. | Case/transaction; duplicate/offline recovery; auth; P0 candidate/1 |
| C-10 Profile/Settings | Consumer; tab. Personal data, language, address, favorites, notification/security/privacy, delete. | Own profile; saved/error; reauth for sensitive actions; P0/1 base; P1/2 extended |
| C-11 Family management | Owner/member; profile. Members, invitation, permissions, dependent profile, shared schedule. | Explicit family grants; invite-expired/revoked; P2/3 |
| C-12 Auth/OTP | Guest/session-expired. Phone, consent, challenge, resend/recovery. | Auth service; invalid/expired/throttled; no account enumeration; P0/0–1 |

## Partner interface

| ID / screen | Purpose and actions | Data/states/permissions/phase |
|---|---|---|
| P-01 Onboarding & verification | Submit business identity, locations, category and evidence; track review. | Verification status, missing/rejected; owner only; P0 candidate/1 |
| P-02 Dashboard | Requests, alerts, fulfillment summary. | Scoped business metrics; empty/offline; granted locations; P1/1–2 |
| P-03 Catalog & availability | Edit products/services, price, stock, hours, capacity. | Versioned catalog; validation/publish states; owner/manager grant; P0 candidate/1 |
| P-04 Order/booking queue & detail | Accept/reject/update assigned business work, communicate, report issue. | Scoped transaction timeline; deadline/late/duplicate states; P0 candidate/1 |
| P-05 Staff and roles | Invite/revoke staff and scope by location/function. | Grant audit; owner/authorized manager; P1/2 |
| P-06 Finance & settlements | View provider-confirmed settlements and reconciliation exceptions. | Finance grant; pending/mismatch; P1/2 |

## Driver/provider interface

| ID / screen | Purpose and actions | Data/states/permissions/phase |
|---|---|---|
| D-01 Availability | Set working state and service area. | Eligibility, location permission; offline/denied; provider's own account; P0 if dispatch model uses it |
| D-02 Assignment | View eligible task, accept/reject before expiry. | Minimal trip/job data; withdrawn/expired; P0 candidate/1 |
| D-03 Active task | Navigate externally/within approved integration, update pickup/progress/completion, incident. | Assigned task only; offline queued update reconciled; P0 candidate/1 |
| D-04 Earnings/support | View approved earnings, payout state, incidents and help. | Own records; pending/mismatch; P1/2 |

## Admin portal

| ID / screen | Purpose and actions | Data/states/permissions/phase |
|---|---|---|
| A-01 Operations dashboard | Health, queues and alerts. | Aggregated minimum data; stale/error; admin grant; P0 candidate/1 |
| A-02 User/partner/provider record | Scoped lookup, verification, restrictions and case-linked review. | Masked data and access purpose; no bulk exposure by default; P0 candidate/1 |
| A-03 Transaction monitor | Inspect linked order/booking/payment event timelines; raise action request. | Immutable references; unknown/mismatch; scoped support/finance; P0 candidate/1 |
| A-04 Refund/dispute queue | Review evidence, request/approve authorized compensation. | Provider status and audit; dual control proposed for threshold; P0 candidate/1 |
| A-05 Moderation & support | Handle reports/cases with reason, outcome, appeal. | Role separation; P0 support, P1 moderation |
| A-06 Policy/configuration | Manage categories, policy versions, service areas and grants. | Change preview/audit/rollback; admin; P1/1–2 |
| A-07 Audit/AI monitoring | Query security/admin/tool execution and usage metrics, not private content by default. | Purpose-bound access; P1/1, advanced later |

## Shared UX requirements

Each mutation returns a persistent transaction reference and user-readable next step. Errors retain safe user input. Empty states say whether no supply exists or the request failed. Permission denials include a manual alternative where possible. Do not show a fake map, live tracking, provider, promotion or payment method when integration/data is absent.
