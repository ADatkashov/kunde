# ADR-021 — Partner directory contract (V9)

- Status: Proposed — prepared under the owner's "architecture first" rule (2026-11-23). The in-process adapter keeps current behaviour and is reversible; extraction-time choices below need owner review.
- Date: 2026-11-23
- Scope: how products (Education, Rides, Leisure, Food, Catalog, Auth) learn whether a partner is APPROVED and whether a user is its ACTIVE staff
- Relates to: [microservice-readiness](../microservice-readiness.md) V9, ADR-018 (partner roles), ADR-014 (unavailable catalog default)

## Context
Partner owns `marketplace.partners` and `partner_staff` and stays in the core (it is the B2B identity every product needs). About 20 SQL references in other
modules join those tables to filter "approved partner" and "active staff", several inside write transactions with `FOR SHARE` locks. A status change
(`PartnerService.decide`) takes `FOR UPDATE` on the partner row, so today a suspension waits for a write that already relied on approval, and no write commits
after the suspension is visible. That invariant is **not documented anywhere**; it only exists because of the joins. If the joins are replaced carelessly it
disappears silently, and if Partner is ever remote it cannot hold.

## Alternatives
1. **Snapshot columns in each product** (`partner_approved`, `partner_name`) updated by Partner events. Removes the join, works across services. But the status is
   eventually consistent: a suspended partner keeps accepting orders until the event arrives, a revoked instructor keeps access, and it needs outbox/inbox first.
   Rejected for write-path decisions; acceptable for display data later.
2. **Leave the SQL joins until extraction.** Zero work now. The coupling stays invisible to the architecture tests only as long as it sits in the baseline, every new
   product copies the pattern, and the lock semantics stay implicit. Rejected: cost grows with every product.
3. **`PartnerDirectory` contract in the platform kernel, in-process adapter in Partner (chosen).** Two kinds of calls: snapshot reads for lists and display, and
   a *locking check* that must run in the caller's transaction and takes the same shared locks the join took. The invariant becomes an interface contract and a test.

## Decision
- `kz.kunde.platform.partner.PartnerDirectory` with `isActiveStaffOfApprovedPartner`, `approvedPartnersOfStaff` (snapshot) and `lockActiveStaffOfApprovedPartner`
  (shared lock until commit). Adapter `partner.JdbcPartnerDirectory`. Role-based authorization (owner/manager/operator) stays in `PartnerService`.
- `PartnerDirectoryConcurrencyIntegrationTest` (committed data, real threads) proves: a suspension waits for a writer holding the lock and every check after it
  sees the suspension. Any future adapter must pass the same test or the product must use re-validation instead (below).
- Migration is per call site, each a small PR that removes baseline lines. First slice: Education instructor checks (`reviewAssignment` with lock, roster and sessions
  as snapshots). Lock order is unchanged: course/cohort rows first, then partner and staff rows; Partner never takes product locks.

## Consequences
- **At extraction** a remote adapter cannot hold a row lock across the network. Write paths that use `lockActiveStaffOfApprovedPartner` then need one of:
  (a) re-validate approval at commit with a version/epoch check, (b) accept a short window and compensate (cancel/refund on late suspension), or
  (c) keep Partner and that product in one deployable. The choice is business-specific (money vs. content) and is **left open for the owner**; the contract marks
  exactly the places where it applies (calls to the locking method).
- Display data (partner name, catalog "approved" filters) will move to the snapshot calls or read models in later slices; these joins need no locking.
- No schema change, no API change, no data migration.

## Not decided
Remote adapter semantics for the locking check; whether catalog listings use a read model; extraction order (see microservice-readiness).
