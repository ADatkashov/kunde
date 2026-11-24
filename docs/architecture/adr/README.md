# Architecture Decision Records

ADRs capture proposed technical decisions for review. “Proposed” is not user approval. A decision changes to accepted only after named owner review; retain superseded records and link replacement ADR.

Partner/Admin roles (D-14): [ADR-018](ADR-018-partner-and-admin-identity-roles.md) is ACCEPTED (2026-11-15) for synthetic DEV; implementation pending, production admin gated.

Identity: [ADR-015](ADR-015-proposed-identity-provider.md) keeps the portable KUNDE identity boundary; amended 2026-11-14 by owner decision to own phone-OTP authentication (no external IdP) for synthetic DEV, production still gated. It does not modify other accepted ADRs. ADR-009 remains the existing provider-pending authentication decision.

Maps (2026-11-22): [ADR-020](ADR-020-kunde-maps-platform-integration.md) (PROPOSED) wires the KUNDE Maps Platform into Rides and Delivery through the existing `RideRouting` seam, flag-gated and internal-only.

Outbox (2026-11-23): [ADR-022](ADR-022-transactional-outbox.md) (PROPOSED) adds the PostgreSQL transactional outbox and inbox (Flyway V68), relay off by default, no producer wired.

Partner directory (2026-11-23): [ADR-021](ADR-021-partner-directory-contract.md) (PROPOSED) turns the "approved partner / active staff" joins into a platform contract with a tested FOR SHARE invariant.

Structure & build (2026-11-24): [ADR-023](ADR-023-build-system-and-module-structure.md) (ACCEPTED 2026-11-24) утверждает multi-module Gradle (Kotlin DSL) для backend с `services/<domain>` при gate эквивалентности. Аудит: [project-structure-audit](../project-structure-audit.md).

Token session (2026-11-24): [ADR-024](ADR-024-shared-token-session-core.md) (ACCEPTED) — общее ядро токен-сессии `packages/kunde_session` и отдельные адаптеры Consumer/Operator (`AuthRepository`) и Partner (`PartnerSession`).
