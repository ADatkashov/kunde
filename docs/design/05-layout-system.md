# 05 — Layout and Responsive System

Mobile-first, content-driven layouts support iOS/Android sizes; breakpoints are working ranges in logical/CSS pixels, not device detection. Design safe content and system bars separately.

## Grid and spacing

| Range | Columns / gutter | Screen margin | Content width / behavior |
|---|---|---|---|
| Compact ≤359 | 4 / 12 | 16 | Single-column; cards stack; hide nonessential labels only when an accessible name remains |
| Mobile 360–599 | 4 / 16 | 20 (16 at compact) | Single-column; horizontal carousels only for secondary discovery modules |
| Tablet 600–899 | 8 / 20 | 24 | Two-column details/master-detail where appropriate; retain mobile navigation structure or rail after research |
| Desktop 900–1199 | 12 / 24 | 32 | Centered content max 1200; side panels for search filters and detail summaries |
| Wide ≥1200 | 12 / 24 | fluid with max 1600 admin | Admin tables use density controls; Consumer/Partner use restrained max widths |

Use 4 px base spacing. Default content vertical gap 16/24; cards padding 16 mobile, 20–24 web. Do not compress critical transaction details to fit one viewport; scrolling is expected and progress/summary remains reachable.

## Safe areas and navigation

- Mobile viewport respects status, camera cutout, home-indicator and keyboard insets. Edge-to-edge backgrounds may extend behind system bars; controls never do.
- Consumer’s five destinations follow PRD: Home, Explore, AI, Activity, Profile. Bottom navigation height includes safe area; labels remain visible. Do not add a sixth primary destination without product review.
- Partner/provider mobile navigation prioritizes queue/task and availability; web Partner uses top bar + collapsible side navigation. Admin uses fixed side navigation with breadcrumbs and page title.
- Search is a first-class entry from Home/Explore; global search retains selected location and category scope.
- Tabs switch within a section and do not replace primary navigation. Back behavior is consistent with platform/system navigation.

## Scroll, modal and keyboard

Use one primary scroll region per screen where possible. Sticky checkout summary is allowed only when it never obscures content and keyboard/focus access remains possible. Bottom sheets use half/full heights according to task; long forms open full-height. Web uses centered dialog for short confirmations and side panel for inspectable detail. Escape/back dismisses only non-destructive transient surfaces; unsaved critical form data warns before discard.

When keyboard opens: scroll focused field into view, keep submit action reachable, do not resize text unexpectedly. Date/time pickers display service time zone and localized format. Maps always have a list/address alternative. Responsive content reflows; avoid horizontal scrolling except data tables with explicit responsive alternatives.

## Tablet and desktop

Consumer tablet can show two-pane explore/detail and larger map/list split. At widths below tablet, stack panes and provide a clear back route. Partner/Admin desktop support dense workflow but default density is comfortable, not maximum. Narrow web shows card/table alternative, filters in drawer and action menu rather than clipped controls.
