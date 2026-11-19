# ADR-019 — One Platform, Multiple Experiences

- Status: Accepted — product direction approved by owner on 2026-11-17; implementation and production rollout remain gated
- Date: 2026-11-17
- Scope: KUNDE participant identities, role boundaries and interfaces
- Supersedes: none; complements PRD 1.0, ADR-015, existing Partner Operations V20

## Context

PRD 1.0 defines four interfaces: Consumer, Partner, Driver/Provider and Admin, plus consumers, families, business partners, service providers/drivers and platform operations. Current DEV has one Flutter consumer APK with a partner hub for approved partner staff, Spring Boot modular monolith, PostgreSQL, and role/membership enforcement. Driver/Provider and full Admin experiences are not yet delivered. The owner confirmed the DEV Partner Operations APK works on a Samsung; that is not production acceptance.

## Decision

**One KUNDE platform, one canonical human identity, exactly four separate applications/interfaces as the target architecture.** Owner confirmed this explicit decision on 2026-11-17. They share one KUNDE Backend and domain contracts, not four independent backend stacks. The four target apps are KUNDE Consumer (Flutter Android/iOS), KUNDE Partner (separate Flutter Android/iOS; web extension optional), KUNDE Provider (separate Flutter Android/iOS for drivers, couriers and field-service providers), and KUNDE Admin (separate protected web application). The existing embedded Flutter partner hub remains operational only as a migration-stage implementation until the standalone Partner app reaches parity; avoid breaking it. Separate app builds, packages, entry points and release pipelines are target deliverables subject to roadmap sequencing, security and CI gates. Do not create speculative microservices.

### Дополнение Control Center 2.0

Требование владельца от 2026-11-19 расширяет поставку KUNDE Admin: единая адаптивная Flutter-кодовая база для закрытого Web, Android, iOS и планшетов. Используем текущую точку входа Admin и общие клиентские компоненты. Все приложения сохраняют один backend и каноническую Identity. Поставка Admin в нативных сборках подчиняется тем же проверкам полномочий Spring Boot и действующим DEV-гейтам.

## Participant model

- Person/User: canonical account and immutable user key; authentication independent of organization and role.
- Organization/Partner: a business entity, potentially with multiple venues.
- Membership: user-to-organization relation with explicit status and scoped permissions.
- Role assignment: CUSTOMER, PARTNER_OWNER, PARTNER_MANAGER, PARTNER_OPERATOR, DRIVER, COURIER, SERVICE_PROVIDER, ADMIN, SUPPORT, FINANCE as *conceptual target roles*, not claims that these exact strings exist today.
- Provider profile and verification: separate from login and organization membership; jurisdiction- and service-specific eligibility.
- A person can be both customer and business owner/worker. Access is authorized per request using role, membership, resource ownership and policy; UI visibility alone is never an authorization boundary.
- Staff revocation must take effect server-side; protect against cross-tenant data access, role escalation and stale claims.

### Experience boundaries

| Experience | Audience | Delivery approach | Current status |
|---|---|---|---|
| KUNDE Consumer | customers and families | Flutter Android/iOS | DEV MVP |
| KUNDE Partner | owners/managers/operators | **separate Flutter Android/iOS application**; optional web extension | partner functionality currently embedded in Consumer DEV APK; standalone app not yet built |
| KUNDE Provider | taxi drivers, couriers, field service workers | **one separate Flutter Android/iOS application** with role-specific workflows | planned |
| KUNDE Admin | platform administrators and support | **one Flutter application** for protected Web and native builds with scoped access | partial Admin APIs and operational queues; full UI planned |

Do not equate a driver with a partner organization: independent providers, contracted fleets and partner employees have distinct membership, verification, payouts and responsibility models. The agreed target is one Provider application with internally separated taxi, courier and field-service workflows; validate operational and regulatory requirements before enabling each workflow.

### Domain boundaries

Preserve the Spring Boot modular monolith and PostgreSQL/Flyway ownership. Existing Order handles purchases, Booking handles time reservations. Future Job/Fulfillment handles assignment and completion; Trip/Dispatch handles transport and location; Payment/Ledger handles provider-confirmed financial state. Do not force transport into Booking. Domain APIs/events, authorization, audit, idempotency and transactional outbox should govern future integration. No speculative tables, migrations, service extraction or deployment in this ADR.

### Safety, compliance and launch gates

Least privilege, scoped audit, consent, data minimization, location access only when required, verified provider eligibility, payment reconciliation and refunds, Kazakhstan personal-data residency/legal review, and independent production security/operational acceptance. DEV mock payment and synthetic providers are not real integrations. AI can prepare proposals but requires explicit user confirmation and ordinary server authorization for execution.

## Consequences

Pros: unified customer journey, shared identity, reusable business modules, independent operator workflows, avoids one overloaded APK and premature microservices. Costs: role/membership complexity, cross-experience contract testing, separate release/security operations when additional apps launch.

## Implementation sequence (not an automatic authorization)

1. Record owner phone verification of Partner Operations in project state.
2. Inventory current identity, partner membership and authorization against this ADR; document actual vs planned without changing working code.
3. Plan a staged extraction of the embedded Partner UI into its own Flutter application without disrupting current DEV client/partner flows; document shared package boundaries, distinct app identifiers, role-aware authentication and independent release pipelines. Complete notification reliability and RU/KK/EN coverage across Consumer/Partner; preserve existing gates.
4. Design and validate provider/fulfillment jobs before courier/driver UI or taxi launch.
5. Defer real payments, regulated mobility, new infrastructure and production rollout pending explicit approvals.

## Acceptance

- No existing Consumer/Partner API or APK behavior changed by this documentation-only decision.
- Existing partner ownership isolation remains mandatory.
- New interfaces reuse canonical user identity and shared domain contracts.
- Future changes are separately scoped and tested, with CI green before merge.
