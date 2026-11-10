# 11 — Admin Portal UX

Admin is a desktop-first operational console with role-specific workspaces, not a universal data browser. Access is case/purpose scoped, fields masked by default, and API authorization is authoritative. See PRD 1.1 roles and Architecture 10/18.

## Shell and information architecture

Persistent left navigation grouped as Operations, Marketplace, Finance, Trust & Support, AI & Data, Administration. Header includes environment label, current role, search by approved transaction/case identifiers, notifications and user menu. Environment is unmistakable in nonproduction. Breadcrumbs and page title include current scope. A global record search returns only authorized results.

## Workspaces

| Area | Table/detail pattern and actions | Permission and safeguards |
|---|---|---|
| Dashboard | Queue aging, order/booking exceptions, payment/refund mismatch, provider health | Aggregated least data; each metric drills into scoped queue |
| Users | Search by verified ID/phone suffix/case; detail has masked profile, sessions and consent status | Support purpose/case required; no bulk browse/export |
| Partners/providers/verification | Status queues, document review, location/catalog/eligibility | Trust role; uploaded evidence private; decision reason and appeal path |
| Categories/services/products | Filterable catalog table and preview; publish/suspend with reason | Moderator/catalog admin; changes versioned and staged |
| Orders/bookings | Dense list filters by status/time/category/provider; timeline detail | Case or operational purpose, minimal beneficiary/customer info |
| Payments/refunds/disputes | Reconciliation exception queue, provider refs, amounts, verified states, evidence, approvals | Finance role; no edit/delete ledger; approval/dual-control if required |
| Promotions | Campaign table, terms, funding, schedule, eligibility | Product/finance grants; preview impact and consent controls |
| Reviews/support/moderation | Case queue, evidence, reply, reason, appeal link | Separation between moderator and finance actions |
| AI operations | Task success/failure/latency/cost/tool-denial metrics; sampled redacted trace only when permitted | AI ops role; private conversation content not default |
| Analytics/reports | Date/region filters, definitions, export request | Aggregate by default; exports reasoned and audited |
| Roles/audit/settings | Grant changes, policy versions, event audit, config history | Admin/MFA, maker-checker for critical change; super-admin break-glass separately |

## Table behavior

Default sort shows highest operational risk/oldest deadline, not arbitrary recency. Columns are configurable but essential state, ID, owner/scope and action remain visible. Filters persist per workspace; chips summarize active filters; saved views avoid sharing sensitive queries. Selection supports bulk actions only when action is safe, reversible and authorized; financial and account-access mutations remain individually reviewed. Pagination is server-side. Row detail opens side panel with timeline; full page for complex resolution.

## States and safety

Loading skeleton preserves table geometry; empty state distinguishes no matching records from no assigned work; error keeps filters and offers retry; stale data has timestamp and disables mutation until refresh. No data is revealed by error details when user lacks permission. Every decision records reason, actor, role, current/next version and correlation ID. Review [`wireframes/admin-dashboard.md`](wireframes/admin-dashboard.md).
