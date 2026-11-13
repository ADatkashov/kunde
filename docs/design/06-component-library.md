# 06 — Component Library

Components use semantic tokens in 04 and accessible names/states in 16. Sizes below are target logical/CSS px; interactive hit regions are ≥44 px, preferred 48 px. All components adapt to locale and text scaling.

## Navigation

| Component | Purpose / structure | Variants, size and states | Behavior / accessibility |
|---|---|---|---|
| Bottom navigation | Four consumer destinations (Home, Search, Orders, Profile; DS-04): icon + label | 56 px bar + safe area; default/selected/disabled | Selected destination announced; never icon-only on supported width; state also conveyed by label/shape |
| Top app bar | Back/title/actions | 56 px mobile, 64 web; standard, search, detail | One H1; actions named; back label context-aware |
| Search bar | Query field + search icon + optional clear/filter | 48–56 px; idle/focused/filled/loading/disabled | Label “Search”; clear button separate; submit via keyboard |
| Tabs | Related local sections | 48 px; selected/unselected/scrollable | Arrow/keyboard navigation web; selected state semantic; avoid tabs as main navigation |
| Side navigation | Partner/Admin sections | 240 px expanded, 72 collapsed | Current route, permission-filtered links, keyboard focus and collapse name |
| Breadcrumbs | Web hierarchy | 32 px row; current/ancestor | Current item nonlink; accessible separators hidden |

## Actions

| Component | Purpose / structure | Variants, size and states | Behavior / accessibility |
|---|---|---|---|
| Primary button | Main next step | Brand fill, 48/56 px; idle/loading/pressed/focus/disabled | One dominant action per region; label starts with verb; loading announced |
| Secondary button | Alternate action | Outlined/surface, 48 px | Pair with primary; do not use for destructive action without explicit label |
| Tertiary button | Low-emphasis action | Text, ≥44 px hit area | Preserve contrast; only one or two per group |
| Icon button | Compact utility | 40–48 px visual/hit region | Tooltip web; accessible name required; avoid ambiguous generic “more” when action known |
| Floating action button | Contextual create action | 56 px, one per screen max | Use only when action is primary, not over maps/status; label announced |
| Destructive button | Cancel/delete/refund action | Error outline/fill after confirmation step | Explicit object/action in label; never rely on red alone; confirmation describes consequence |

## Inputs

| Component | Structure/size | States and behavior | Accessibility |
|---|---|---|---|
| Text field | Persistent label, 48–56 px, optional helper/counter | Empty/focused/filled/error/disabled/read-only | Label not placeholder-only; error linked and announced |
| Password | Label, reveal toggle | Hidden/revealed/error | Toggle name changes “Show/Hide password”; secure entry |
| Phone input | Country code + national number | Input/verification/pending/error | Locale-aware formatting; country selection announced; preserve normalized value safely |
| Search input | Search field + clear/filter controls | Query/debounce/loading/no result | Search role, submit action; clear separate from field |
| Dropdown/combobox | Label, selected value, option list | Open/selected/empty/disabled | Keyboard typeahead, selected semantics; searchable when long |
| Date picker | Calendar plus date field | Available/selected/disabled/loading | Localized weekdays, keyboard and screen-reader date; no color-only disabled slots |
| Time picker | Slot list or time field | Available/held/taken/selected/expired | Announce time zone and slot status; concurrent availability rechecked |
| Location picker | Search/address list/map alternative | Permission/typing/selected/out-of-area/error | Manual entry always available; map is not sole path |
| Checkbox | Label + box | Checked/unchecked/mixed/disabled | Group label, native semantic; consent unchecked by default |
| Radio | Mutually exclusive options | Selected/unselected/disabled | One accessible group label; keyboard arrows |
| Switch | Immediate binary preference | On/off/pending/disabled | Verb phrase label explains effect; use for immediate setting, not consent/legal agreement |
| Slider | Bounded continuous/range value | Min/max/current/disabled | Numeric value and keyboard increments announced; offer direct numeric input when precision matters |

## Content and data

| Component | Purpose / structure | Variants and behavior | Accessibility |
|---|---|---|---|
| Category card | Icon/illustration, category title, optional subtitle | Grid/list; available/coming later | Whole card one link; announce availability; no emoji production icon |
| Business card | Logo/photo, name, category, rating count, distance/status | Compact/standard/featured | Rating text “4.8, 236 reviews”; image alt or decorative; availability not implied by card presence |
| Restaurant card | Business card + delivery/pickup/estimated time | Only verified fulfillment data shown | Distinguish estimate from confirmed time |
| Product card | Image, name, options/price/stock | Grid/list; unavailable/sale | Name/price/stock in logical order; option count accessible |
| Service card | Service, provider, price model, duration/availability | Fixed/estimate/quote | Price model verbally stated; “from”/estimate explained |
| Provider card | Name/verified credentials/area/rating | Individual/business | Show only verified/approved claims; avoid trust badge without criteria |
| Driver card | First name/photo/vehicle/plate only after assignment | Assigned/current trip | Privacy-minimized; announce relevant data; no exposure to unrelated roles |
| Promotional banner | Offer, eligibility, expiry, action | Image/text; active/expired/ineligible | Terms accessible before claim; no flashing/auto-rotation |
| Rating | Stars + numeric + count | Read-only/input/review eligibility | Numeric text/label; keyboard selection; not color-only |
| Price summary | Line items, fees, discount, total, currency | Estimate/quote/final/pending | Exact total and currency; accessible math/order; material changes highlighted |
| Address summary | Label, formatted address, edit action | Home/work/custom/invalid | Full address available to screen reader; selected state announced |
| Status timeline | State, timestamp, actor/user-safe note | Order/booking/payment/refund | Pending vs confirmed explicit; chronological semantic list |

## Feedback and states

| Component | Use / structure | Variants / behavior | Accessibility |
|---|---|---|---|
| Toast | Noncritical short confirmation | Auto-dismiss ≥4 s; no critical transaction state | Live region polite; do not include only place status here |
| Snackbar | Reversible action/brief update | Message + optional Undo | Focus-safe and action reachable; timeout pauses on focus |
| Dialog | Blocking decision or destructive confirm | Short content; explicit primary/secondary | Focus trap web, restore focus, title/description semantics |
| Bottom sheet | Context/detail/action selection | Peek/half/full | Modal semantics, drag not sole dismissal; close button |
| Alert | Inline local warning/error | Info/warning/error | Icon + heading/message, announced once |
| Progress indicator | Indeterminate/determinate work | Linear/circular; % only if meaningful | Announce progress; no fake precision |
| Skeleton | Loading layout placeholder | Match content geometry | Mark busy and hide decorative skeleton from screen reader |
| Empty state | No content/result | Icon/heading/explanation/action | State explains why and next step; not an illustration alone |
| Error state | Recoverable/terminal failure | Retry/support/back | Stable message, no stack trace, preserve safe inputs |
| Offline state | Network unavailable/stale cache | Banner/inline | Explain actions requiring connection; no stale transaction claims |

All variants must be designed for Light/Dark, Kazakh/Russian text expansion, 200% text scaling and narrow screens. Component API names and component behavior are handed off via Figma naming in 19.
