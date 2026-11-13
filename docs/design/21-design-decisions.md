# 21 — Design Decisions and Open Questions

All decisions are **recommendations** unless explicitly traced to a product requirement. Visual decisions require user research and brand review; this spec does not declare a final logo or approved identity.

## Proposed decisions

| ID | Recommendation | Reason | Alternative | Revisit / validation |
|---|---|---|---|---|
| DS-01 | Calm Teal + Warm Mineral direction | Calm trust, readable daily utility, localizable | Urban Ink/Apricot; Cobalt/Lime | Test brand recall and perceived trust with Almaty consumers and merchants |
| DS-02 | Deep evergreen primary interaction color; warm off-white canvas | Differentiation with strong WCAG text contrast | Blue-led palette | Contrast and user preference testing |
| DS-03 | Inter with Noto Sans/system fallback, only after glyph/license audit | Neutral and readable multilingual baseline | Platform system fonts only | Confirm all Kazakh Cyrillic glyphs/weights/licensing on target devices |
| DS-04 | Consumer bottom nav has four destinations: Home, Search, Orders, Profile; AI is a Home block | Owner decision 2026-11-13 (visual reference review); avoids a dead AI tab while AI is unavailable | PRD-1.0 five destinations (Home, Explore, AI, Activity, Profile) | Navigation comprehension study; PRD-1.0 §consumer navigation still says five and needs the owner's update |
| DS-05 | List-first discovery with map as optional synchronized view | Accessibility and comparison | Map-first mobility pattern | Research category-specific; never force map for all categories |
| DS-06 | Separate category-specific checkout/booking/dispatch forms | Prevents a generic but misleading flow | One universal cart/checkout | Keep category-specific contract from PRD/Architecture |
| DS-07 | AI preview and action confirmation are distinct surfaces | User control and financial safety | Confirm inline in chat | Usability test while preserving explicit exact-draft confirmation |
| DS-08 | Role-specific Partner/Provider/Admin density with shared foundations | Different operational work without fragmented brand | One shared navigation/UI | Validate role workflows; maintain shared token/component base |
| DS-09 | Full Light and Dark semantic token sets | User/platform preference and contrast | Light only initially | Confirm support/QA/device demand before launch |
| DS-10 | Show only operationally ready categories as actionable | Avoid false marketplace promise | Show full taxonomy with locked states | Product/operations approve what is discoverable per market |

## Open decisions

- Final logo/mark, trademark review, illustration/photo art direction and brand lockup translations.
- User research sample, priority audience and usability test success thresholds.
- Font asset licensing, final family/subsets and supported OS/browser matrix.
- Whether Dark theme is launch P0 or post-pilot; design tokens support it either way.
- Which categories/partners/fulfillment types are live at launch.
- Map availability/coverage and whether map view is useful for each service category.
- Exact payment-method presentation, cancellation/refund copy and partner/provider SLAs.
- Final content approval workflow for Kazakh, Russian and English; source translation review.
- Loyalty, promotions, rating incentives and family/health screen enablement depend on separate product decisions.

## Reconciliation with product and architecture

No conflict with PRD five tabs/eight categories/phased MVP, PRD separation of orders/bookings/payments, AI confirmation rules, family privacy or architecture Flutter/backend recommendations. The existing demo app’s teal palette is a seed implementation, not an approved brand decision; this proposed palette may be adjusted after contrast review. PRD mentions loyalty as a profile capability but treats loyalty marketplace as out of initial MVP; UI reserves it and does not expose a nonfunctional screen. Architecture recommends web-oriented partner/admin surfaces; this UX spec uses responsive web as a proposal while keeping provider surface mobile-first.

## Risks and research questions

Risk: teal may look generic; mitigate with distinctive wordmark, local editorial photography and motion restraint. Risk: five destinations create dense Home/Explore overlap; test where category/search entry belongs. Risk: premium spacing can slow dense partner workflows; use role-specific density. Risk: translations expand labels; prototype real language content. Risk: Dark status colors differ by theme; test all pairings. No hypotheses should be presented as validated user behavior.
