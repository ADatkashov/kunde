# 09 — Consumer Mobile Roadmap

Build the Flutter consumer app as a client of the Spring REST API; business eligibility, prices, authorization and order state remain server-authoritative.

1. Foundation: app structure, environment config, navigation, theme/design tokens, accessibility primitives, localization, error/loading/empty/offline states and API client.
2. Identity/onboarding: approved sign-in, session expiry/recovery, consent and profile, tested for localization and device permission denial.
3. Location/home: address selection, serviceability, curated home and category-disabled/out-of-zone states.
4. Explore/search: localized catalog results, filters only when supported, empty/error states, partner and offering detail.
5. Transaction: one merchant-scoped cart, server quote/validation, final price and policy confirmation, duplicate-submit protection and payment challenge/status.
6. Activity/support: order history/detail, accurate status timestamps, cancellation eligibility, refund status, support contact and notifications.
7. Later: bookings, reviews, promotions, richer AI search; action preparation only with explicit reviewed summary and user confirmation.

Shared components precede screens: tokenized typography/color/spacing, form/validation, buttons, list/card, price display, loading/error/empty, consent, accessibility semantics, localized date/money and API error mapping. Follow design docs 04–18; do not duplicate domain rules in Dart. Every consequential operation displays the server result and recoverable error path.

