# 20 — Design QA

Design QA covers visual consistency, behavior, accessibility, localization, theme and state coverage. A “ready” screen includes loading/empty/error/offline/permission/payment state as applicable, not just the default frame.

## Cross-product checklist

- Brand/logo and semantic tokens used consistently; no unapproved colors or unsupported category promotion.
- Type hierarchy and contrast match specs; no text clipping at 200% scale or Kazakh/Russian expansion.
- Interaction control has visible focus/pressed/disabled/loading state and min hit target.
- Primary action, next state, cancellation terms and status freshness are clear.
- Components expose screen-reader semantics and do not use color alone.
- Light and Dark themes are designed and checked; system preference respected.
- 360 px compact, 390 px common mobile, large phone, tablet, desktop and wide layouts checked.
- Keyboard, safe area, gesture/back, modal focus and reduced motion checked.
- Empty/offline/error states offer appropriate next step and preserve safe user input.
- Payment pending/unknown and refund pending never appear as success; user is not prompted to duplicate charge.
- Exact content, image license/consent, localization strings and accessibility labels are reviewed.

## Interface-specific checklists

### Consumer

- Exactly five primary destinations; labels visible; location is obvious/editable.
- Search/category listing indicates serviceability/freshness; map has text list fallback.
- All eight category flows match domain-specific pattern; disabled/unready categories cannot proceed.
- Cart/quote/booking/AI review shows provider, beneficiary, amount, currency, time/location and policy before commit.
- AI distinguishes information/recommendation/draft/action; each paid action gets a separate confirmation.
- Activity separates order, booking, payment and refund states; support entry is findable.

### Partner

- Active tenant/location scope obvious; unauthorized sections absent and API remains protected.
- Accept/reject deadline, price and customer instructions visible; duplicate/late command states covered.
- Catalog draft vs published and price/availability impact clear.
- Calendar avoids double-booking; finance/payout screens gated by role.

### Provider

- Task type and next safe action immediately visible; buttons one-handed and ≥48 px.
- Driving states discourage unsafe interaction; map has text route fallback.
- Online, offer expiry, assignment revoked, offline queued and confirmed status distinct.
- Customer location/contact minimized; earnings displayed only if enabled and verified.

### Admin

- Environment/role/scope visible; personal fields masked; case/purpose gate present.
- Tables filter, sort, paginate and preserve essential state on narrow widths.
- Bulk action preview/permission and undo where safe; finance actions individually reviewed.
- Audit timeline, maker/checker and appeal path visible where relevant.

## Release evidence

Capture review matrix per Screen ID: device/viewport, theme, locale, state, accessibility check, owner, issue and disposition. Verify contrast computationally and visually in composed states. Product/operations sign off supply/status language; legal reviews prices, cancellation, consent and category-specific disclosure. Critical accessibility or financial-state ambiguity blocks handoff.
