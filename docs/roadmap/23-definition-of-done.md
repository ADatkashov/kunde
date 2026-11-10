# 23 — Definition of Done

## Feature

Acceptance criteria pass for allowed and denied paths; linked PRD/story is traceable; UX, accessibility, localization and analytics are addressed; API behavior is documented; support and release behavior are reviewed; product owner accepts evidence.

## Backend task

Reviewed code, domain boundary respected, unit/integration/API tests pass, validation and idempotency/error behavior are explicit, authz and PII logging reviewed, metrics/audit added where needed, OpenAPI/runbook updated.

## Mobile task

Reviewed implementation uses tokens/shared components, handles loading/empty/error/offline/session states, accessibility and localized content pass, no business rule is client-authoritative, API contract and supported device behavior verified.

## Web/admin task

Role/scope checks enforced server side, sensitive values minimized, audit trail complete, keyboard/accessibility/localization reviewed, misuse/negative permission paths tested and operator instructions updated.

## Database change

Domain owner approves migration, constraints/indexes and retention classification; migration is forward-compatible for supported app/API versions; rollback/compensation plan exists; backup and data safety reviewed; integration tests pass.

## Integration

Contract, sandbox and failure cases pass; credentials stored safely; timeout/retry/signature/idempotency and reconciliation behavior proven; cost/data terms and fallback documented; production readiness approved by owner.

## Security task / bug fix

Threat or defect root cause addressed; regression/negative tests added; logs do not expose secrets/PII; severity and residual risk reviewed; affected runbook or user communication updated.

## Epic and release

All in-scope features/tasks accepted, no open critical defects or unowned high risks, operational/security/legal gates satisfied, dashboards/runbooks/support owners ready, migration/client compatibility checked, release evidence and rollback/pause plan recorded. Code completion alone is never release readiness.

