# 19 — Figma Handoff Specification

This document prepares the design handoff; **do not create or edit a Figma file as part of this task**. Figma structure is a proposed source of truth for visual artifacts; this repository remains the current specification baseline.

## File/page structure

1. `00 Cover & Read Me` — version, status (proposal), links, device frames, owners.
2. `01 Brand Foundations` — positioning, logo explorations (clearly unapproved), icon/photo direction.
3. `02 Color Styles` — primitive and semantic Light/Dark tokens, contrast notes.
4. `03 Typography` — font/glyph review, scale, localized specimens.
5. `04 Design Tokens` — space, radius, elevation, breakpoints, motion, z-index.
6. `05 Components` — grouped foundations/navigation/actions/inputs/content/feedback.
7. `06 Consumer App` — Home, Search, Orders, Profile (AI as Home block), category prototypes.
8. `07 Partner App` — onboarding, queue, catalog, calendar, finance.
9. `08 Provider App` — availability, offer, active task, incident.
10. `09 Admin Portal` — queues, detail, finance, moderation, roles/audit.
11. `10 Flows & Prototypes` — links to user flows and branch states.
12. `11 Developer Handoff` — spec status, token mapping, exports, unresolved issues.

## Naming conventions

- Pages: numeric prefix + Pascal Case (`06 Consumer App`).
- Components: `Category/Component/Variant/State`, e.g. `Action/Button/Primary/Loading`; component property names are `Size`, `Theme`, `State`, `Icon`, `Label`, `Density`.
- Frames: `APP/ScreenID/Screen name/Breakpoint/Theme/Locale/State`, e.g. `C/C-17 Checkout/Mobile/Light/ru-KZ/PriceChanged`.
- Layers: descriptive semantic names (`Header/LocationSelector`, `Order/PaymentStatus`), no `Frame 1`, no raw hex names.
- Variables: mirror token path `color/light/text/primary`, `space/4`, `type/body/medium` and semantic names from JSON. Any intentional exception is documented.

## Variant and handoff rules

Component variants cover meaningful behavior, not cosmetic combinations without use. Show default/focus/pressed/disabled/loading/error/selected states where applicable, plus Light/Dark and locale expansion. Publish component descriptions: purpose, responsive behavior, accessibility name, min target, content limits and related PRD requirement. Use Auto Layout and min/max constraints; no fixed text heights. Prototype must include failure and alternate branches for checkout/payment/booking/AI, not only happy path.

## Design-to-dev package

Provide token JSON version, asset export list/license, font license/glyph report, redline or inspect data, component behavior, responsive breakpoints, interaction/motion specs, copy keys and accessibility notes. Link every key frame to Screen ID and Requirement ID. Mark designs `Exploration`, `Ready for review`, `Approved`, `Superseded`; only named approver may set Approved. Developer handoff records platform-specific differences rather than hiding them.
