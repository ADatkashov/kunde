# 08 — Consumer Mobile Architecture

## Recommendation and layers

Use Flutter with a feature-first structure and explicit presentation/domain/data layers:

```text
app shell/navigation
  features/{auth,home,search,catalog,cart,orders,bookings,activity,profile,family,ai,support}
  shared/{design_tokens,localization,networking,auth_session,analytics,accessibility}
  platform adapters/{secure_storage,push,location,deep_links}
```

State management can use one team-standard predictable approach; the decision is implementation detail, provided state is testable and side effects live in repositories/services. Avoid a monolithic widget tree and avoid generic “super-app” plugin coupling.

## Client responsibilities

- Render localized/accessibility-ready UX and validate input for usability; server remains authoritative.
- Maintain ephemeral UI state and safe drafts. Persist only required encrypted session/token references via platform secure storage; do not cache sensitive child/health/payment details by default.
- Attach idempotency keys to mutations and retain them across retry/reconnect; query state after timeout before another command.
- Support deep links to authenticated transaction details; never trust IDs in link without server authorization.
- Expose loading/empty/offline/error/unknown states explicitly. Browse cache can be stale-labeled; checkout, slot reservation, payment and cancellation require online revalidation.
- Request location/push permissions contextually; manual address and in-app notification center remain alternatives.
- Instrument app launch, route, crash, network and funnel events with privacy filtering.

## Feature ownership

Each feature owns routes, view models/state, API DTO mapping and UI tests; shared packages provide design tokens, error envelope, locale formatting, auth and telemetry. Keep provider-specific SDKs behind platform adapters. Accessibility semantics, text scaling and keyboard/screen reader behavior are release requirements.

## Data/cache and release

Secure storage is for credentials/session secrets only. Local database cache, if introduced, has per-entity TTL and logout/deletion purge behavior. App config supplies API base URL/environment; secrets and privileged credentials must never ship in client bundle. Store review, feature flags and backward API compatibility are independent release controls. Crash reporting and analytics vendors require privacy/region due diligence.
