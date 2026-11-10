# 13 — Screen Inventory

Screen IDs are unique across applications: **C** Consumer, **P** Partner, **D** Driver/Provider, **A** Admin. Priorities follow PRD 1.1; “Specified” means functional UX is documented, not visually approved. Components use 06; related stories/flows use PRD 1.1 docs 03–04 and design doc 12. Shared state behavior is in 14.

## Consumer — 35 screens

| ID | Screen | Purpose / key components | Priority | Related stories/flow | Status |
|---|---|---|---|---|---|
| C-01 | Launch/session check | Restore valid session, route safely | P0 | AUTH-002 / Identity | Specified |
| C-02 | Phone entry | Registration/login start, consent | P0 | AUTH-001 / Identity | Specified |
| C-03 | OTP verification | Verify challenge, resend timer/recovery | P0 | AUTH-001/002 / Identity | Specified |
| C-04 | Profile onboarding | Optional name/locale/preferences | P0 | USER-001 | Specified |
| C-05 | Home | Location, search, AI, supported categories, live activity | P0 | HOME-001–004 / Discovery | Specified |
| C-06 | Explore categories | Browse eight-category taxonomy, only operational categories active | P0 | EXP-001 | Specified |
| C-07 | Global search | Search/facets/recent queries | P0 | SEARCH-001–003 / Discovery | Specified |
| C-08 | Filter/sort sheet | Filters, sort, clear/apply | P1 | EXP-002 | Specified |
| C-09 | Map/list results | Compare nearby results, selected pin/list sync | P1 | SEARCH-001 | Specified |
| C-10 | Category landing | Category-specific subcategories | P0 conditional | EXP-001 | Specified |
| C-11 | Business detail | Business profile, catalog, hours, terms | P0 conditional | EXP-001 | Specified |
| C-12 | Product detail | Options, stock, quantity, add | P0 conditional | FOOD-001 | Specified |
| C-13 | Service detail | Scope, provider, price model, availability | P1 conditional | HOME-005/CARE-001 | Specified |
| C-14 | Address picker | Saved/manual/map alternative | P0 | USER-002 | Specified |
| C-15 | Address editor | Create/edit validation and service area | P0 | USER-002 | Specified |
| C-16 | Cart | Merchant-scoped lines/options | P0 conditional | ORDER-001 | Specified |
| C-17 | Checkout/review | Address, fulfillment, quote, payment selection | P0 conditional | ORDER-001/002 | Specified |
| C-18 | Payment result | Pending/verified/failure result | P0 conditional | PAY-001 | Specified |
| C-19 | Booking slot picker | Date/staff/resource/availability | P1 | BOOK-001 | Specified |
| C-20 | Booking review | Beneficiary, slot hold, total, terms | P1 | BOOK-001/002 | Specified |
| C-21 | Mobility request | Pickup/dropoff/tier/fare estimate | P0 conditional | MOB-001 | Specified |
| C-22 | AI conversation | Search/help/compare/tool status | P1 | AI-001 | Specified |
| C-23 | AI action preview | Exact draft and confirmation | P1 future execution | AI-002/003 | Specified |
| C-24 | AI task detail/history | Per-step status, retry/cancel/context control | P2/P1 | AI-004/005 | Specified |
| C-25 | Activity list/detail | Orders, bookings, payments, receipt | P0 | ACT-001 | Specified |
| C-26 | Transaction tracking | Timeline/map if verified, cancellation/support | P0 conditional | ORDER-003 | Specified |
| C-27 | Booking detail | Status, time zone, reschedule/cancel | P1 | BOOK-002 | Specified |
| C-28 | Refund detail | Amount/state/next steps | P0 conditional | PAY-001 | Specified |
| C-29 | Profile & settings | Personal info, language, favorites, prefs | P0/P1 | USER-001/003 | Specified |
| C-30 | Payment methods | Provider flow/token refs | P0 conditional | PAY-001 | Specified |
| C-31 | Family management | Invite/member permissions/beneficiary | P2 | FAM-001/002 | Specified |
| C-32 | Reviews | Eligible reviews and own submissions | P1 | Review stories/BR-013 | Specified |
| C-33 | Notifications center | Transaction/security notices and settings | P0 | USER-003 | Specified |
| C-34 | Privacy/security | Devices, consent, export/delete | P1 | USER-004 | Specified |
| C-35 | Support center/case | Help, case creation/replies/evidence | P0 | SUP-001 | Specified |

## Partner — 25 screens

| ID | Screen | Purpose / key components | Priority | Story | Status |
|---|---|---|---|---|---|
| P-01 | Sign in | Business role authentication | P0 | PARTNER-001 | Specified |
| P-02 | Business registration | Owner and organization details | P0 conditional | PARTNER-001 | Specified |
| P-03 | Verification checklist | Status, requirements, remediation | P0 | PARTNER-001 | Specified |
| P-04 | Document upload | Private evidence upload/replacement | P0 conditional | PARTNER-001 | Specified |
| P-05 | Onboarding completion | Locations, category, hours, fulfillment | P0 conditional | PARTNER-001 | Specified |
| P-06 | Dashboard | Alerts, requests, active work | P1 | PARTNER-002 | Specified |
| P-07 | Orders queue | Filterable new/active/completed work | P0 conditional | PARTNER-002 | Specified |
| P-08 | Order detail | Accept/reject/prepare/update | P0 conditional | PARTNER-002 | Specified |
| P-09 | Booking queue | Confirm/reject/reschedule requests | P1 | BOOK-001/002 | Specified |
| P-10 | Calendar/resources | Staff/resource capacity and closures | P1 | BOOK-001 | Specified |
| P-11 | Business profile | Public profile/localized details | P0 conditional | PARTNER-001 | Specified |
| P-12 | Location/branch list | Branch settings and service area | P0 conditional | PARTNER-001 | Specified |
| P-13 | Product catalog | Items, modifiers, stock and publish | P0 conditional | FOOD-001 | Specified |
| P-14 | Service catalog | Service scope, duration, resources | P1 | Category stories | Specified |
| P-15 | Categories and pricing | Category assignment, fixed/estimate/quote models | P0/P1 conditional | PARTNER-001 | Specified |
| P-16 | Availability/hours | Hours, capacity and exception dates | P0 conditional | PARTNER-001 | Specified |
| P-17 | Employees/roles | Invite, scope, revoke | P1 | PARTNER-002 | Specified |
| P-18 | Customers | Scoped transaction contact/detail only | P2 | Partner operations | Specified |
| P-19 | Promotions | Terms, eligibility, schedule | P2 | HOME-004 | Specified |
| P-20 | Analytics | Aggregate business and fulfillment metrics | P2 | Partner operations | Specified |
| P-21 | Reviews | Review response/report workflow | P1 | OPS-002 | Specified |
| P-22 | Payouts | Settlement and reconciliation status | P1 | FIN-001 | Specified |
| P-23 | Documents | Business records, expiry and review states | P0 conditional | PARTNER-001 | Specified |
| P-24 | Support | Partner cases and incident communication | P0 | SUP-001 | Specified |
| P-25 | Settings | Business preferences and authorized account controls | P1 | PARTNER-001 | Specified |

## Driver/Provider — 16 screens

| ID | Screen | Purpose / key components | Priority | Story | Status |
|---|---|---|---|---|---|
| D-01 | Sign-in/role selection | Auth and explicit provider role | P0 conditional | PROVIDER-001 | Specified |
| D-02 | Eligibility status | Verification, missing/expired evidence | P0 conditional | PROVIDER-001 | Specified |
| D-03 | Document capture | Secure upload, scan/crop, status | P0 conditional | PROVIDER-001 | Specified |
| D-04 | Availability home | Online/offline and service area | P0 conditional | PROVIDER-001 | Specified |
| D-05 | Incoming request | Scope, fare/quote basis, deadline | P0 conditional | PROVIDER-001 | Specified |
| D-06 | Accept/reject confirmation | Explicit response and reason | P0 conditional | PROVIDER-001 | Specified |
| D-07 | Active task | Step state and main action | P0 conditional | PROVIDER-001 | Specified |
| D-08 | Navigation/address | Map or text directions, contact limits | P0 conditional | PROVIDER-001 | Specified |
| D-09 | Pickup/arrival | Verify pickup/arrival state | P0 conditional | PROVIDER-001 | Specified |
| D-10 | In-progress work | Job/trip/visit progress | P0 conditional | PROVIDER-001 | Specified |
| D-11 | Completion/evidence | Complete task, proof, incident | P0 conditional | PROVIDER-001 | Specified |
| D-12 | Earnings/payouts | Own verified earnings only | P1 | FIN-001 | Specified |
| D-13 | Rating/history | Own completed task history | P1 | Review stories | Specified |
| D-14 | Notifications | Assignment and security notices | P0 | PROVIDER-001 | Specified |
| D-15 | Support/incident | Report safety/service issue | P0 conditional | SUP-001 | Specified |
| D-16 | Settings/devices | Language, permissions, security | P0 | AUTH-002 | Specified |

## Admin — 25 screens

| ID | Screen | Purpose / key components | Priority | Story | Status |
|---|---|---|---|---|---|
| A-01 | Secure sign-in/step-up | Privileged authentication | P0 | ADMIN-001 | Specified |
| A-02 | Operations dashboard | Queue health and exceptions | P0 | OPS-001 | Specified |
| A-03 | Users | Scoped masked lookup and cases | P0 | OPS-001 | Specified |
| A-04 | User detail/security | Sessions, consent, account restrictions | P1 | AUTH-002/OPS-001 | Specified |
| A-05 | Partners | Verification and status queue | P0 | PARTNER-001 | Specified |
| A-06 | Partner detail | Business/location/catalog review | P0 | PARTNER-001 | Specified |
| A-07 | Providers | Eligibility and incident queue | P0 conditional | PROVIDER-001 | Specified |
| A-08 | Provider detail | Documents/assignment eligibility | P1 | PROVIDER-001 | Specified |
| A-09 | Category configuration | Supported categories/service areas | P1 | ADMIN-001 | Specified |
| A-10 | Service moderation | Service quality and policy decisions | P1 | OPS-002 | Specified |
| A-11 | Orders monitor | Search and linked timeline | P0 | OPS-001 | Specified |
| A-12 | Bookings monitor | Slot/provider exception queue | P1 | OPS-001 | Specified |
| A-13 | Payments monitor | Verified provider/internal state | P0 | FIN-001 | Specified |
| A-14 | Refund queue | Review/approve/refund states | P0 | PAY-001/FIN-001 | Specified |
| A-15 | Disputes | Evidence, reply, decision/appeal | P0 | OPS-001 | Specified |
| A-16 | Promotions | Eligibility/funding and review | P2 | HOME-004 | Specified |
| A-17 | Reviews moderation | Reports, reasons, appeals | P1 | OPS-002 | Specified |
| A-18 | Support cases | Assignment, response, resolution | P0 | SUP-001/OPS-001 | Specified |
| A-19 | AI operations | Task/tool/cost metrics, redacted traces | P1 | AI-001–005 | Specified |
| A-20 | Analytics | Metric dashboards and definitions | P1 | FIN-001/ADMIN-001 | Specified |
| A-21 | Roles/permissions | Scoped grants and access reviews | P0 | ADMIN-001 | Specified |
| A-22 | Audit logs | Searchable privileged/security event audit | P0 | ADMIN-001 | Specified |
| A-23 | Product moderation | Product catalog review and report decisions | P1 | OPS-002 | Specified |
| A-24 | Reports/exports | Aggregate report and controlled export | P1 | ADMIN-001 | Specified |
| A-25 | System settings | Integrations, feature/policy configuration and health | P1 | ADMIN-001 | Specified |

## Coverage summary

This inventory specifies **101 screens**: 35 Consumer, 25 Partner, 16 Provider and 25 Admin. Priority conditional means the screen is designed but must remain disabled until supply, fulfillment, security and support readiness is confirmed. Visual design status for every screen is “Specified”; no Figma designs have been approved.
