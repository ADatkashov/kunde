# 09 — Partner Application UX

## Product surface and navigation

Recommend a responsive Partner web console with mobile-friendly task actions, not a separate app until partner research proves need. Side navigation: Overview, Orders & Bookings, Calendar, Catalog, Locations, Customers (transaction-scoped), Team, Promotions (when enabled), Reviews, Finance, Documents, Support, Settings. Top bar includes tenant/business and location switcher, alerts, profile and help. Every screen reflects the active business/location scope; role grants hide unavailable navigation and APIs still enforce access.

## Onboarding and verification

| Screen | Main content/actions | States and safeguards |
|---|---|---|
| Registration | Owner identity, phone/email, consent, credentials flow | Verification pending; resend limited; no duplicate business assumption |
| Business details | Legal/trading name, type, country, contacts, tax identifiers as required | Save draft; validation; sensitive values masked; regional legal review |
| Location setup | Address, service area, hours, fulfillment modes | Manual map/list entry; location unavailable; validate service area |
| Documents | Requirements by category, secure upload, review status | Pending/rejected/expired; reason and replacement path; private files |
| Review status | Checklist, review timeline, contact support | Not orderable until approved; no fabricated turnaround promise |

## Daily workflow

**Overview dashboard:** KPI cards only for scoped verified metrics: new requests, response deadlines, active fulfillment, availability, alerts. Cards link to actionable queues; do not overload with generic vanity charts.

**Orders queue:** tabs New, Active, Completed, Needs attention. Row shows order ID, received time, promised deadline, item count/fulfillment, value if role permits, and state. Detail shows current server state, customer instructions limited to fulfillment need, item availability, exact quote and accept/reject actions. Rejection needs reason; acceptance may trigger preparation workflow; late responses visibly flagged. Duplicate/out-of-scope actions return current state.

**Bookings/calendar:** calendar day/week plus accessible list; filter location, staff and service. Slot inventory, holds, confirmed bookings and blocked hours are distinct. Do not allow a manager to double-book by drag interaction; server revalidates and explains collision. Customer details minimized to visit need.

**Catalog:** separate Products, Services, Categories & Pricing, and Availability screens. Each lists status, localized title/description, price model, stock/options or service duration/resource, schedule and preview. Separate draft/published; changes affecting active quote/booking show impact before publishing. Bulk edit requires preview and role. Out-of-stock/suspended state clear.

**Locations/team:** locations, service areas, hours and staff/resource assignment; owner invites scoped role. Roles are least-privilege; employees see tasks and catalog fields required for job, not payouts or unrelated customer history. Customer, promotion, analytics, review response, payout, document, support and settings each have separate entry screens and explicit grants.

## Finance, promotion and reputation

Finance area shows pending/confirmed settlements, fees and reconciliation exceptions only to authorized finance/owner. Never present customer charge as partner payout. Promotions require funded/approved eligibility and clear start/end/cap; disabled until product/finance policies exist. Reviews display eligible public content and response workflow; report/moderate is separate. Documents and support cases remain scoped to business and uploader.

## Screen states and responsive behavior

All list screens support search/filter/sort/pagination, skeleton, no-data state, API error with retry and permission-denied state. Offline mode marks cached queue stale and disables accept/reject/price edits. Desktop uses persistent side nav and detail pane; tablet collapses nav; mobile uses drawer/nav rail and full-screen forms. Tables collapse to labeled cards below 720 px; never hide status/deadline/actions in horizontal scroll alone.

## Visual wireframe order

Page title + active location → task/alert summary → new request queue → active booking/order snapshot → quick actions. Use warm neutral canvas, compact but generous line-height, semantic badges and teal primary actions. Review [`wireframes/partner-dashboard.md`](wireframes/partner-dashboard.md).
