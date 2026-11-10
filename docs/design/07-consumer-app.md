# 07 — Consumer Super App

## Navigation and shared shell

Five bottom destinations: **Home, Explore, AI, Activity, Profile**. Keep labels visible and stable across app releases. Search and city/address selector persist across Home/Explore. Orders/Bookings are never combined into one ambiguous status. Unsupported categories are hidden or explicitly marked unavailable; no dead-end “coming soon” cards in launch primary surface. Core actions respect the server as source of truth and reflect pending states.

## Home

### Home screen anatomy

1. Safe-area top row: KUNDE wordmark or compact mark, selected city/address with change affordance, notification entry with unread count.
2. Greeting uses display name only if available; otherwise neutral greeting. Do not expose family/health context on lock screen.
3. Global search field (“What do you need today?”) opens Explore with selected location and recent queries.
4. AI entry card uses distinct AI label, one-line capability, and example prompt; never implies autonomous completion.
5. Category grid shows only serviceable categories (two columns mobile, up to four tablet); category icon, clear title, optional short descriptor.
6. Active orders/bookings module appears only when relevant, with type/status and “View details”.
7. Nearby/popular/recommended business cards and promotions only when sourced, current and eligible; include “why this” or location context if personalized.
8. Recently viewed is optional, user-controlled and clearable; not shown for sensitive health/child contexts by default.

Home can be location-specific and personalized, but user must see/change location. Loading uses content skeleton; first-use empty state explains no live services and links to choose another area; error offers retry; offline cached modules are marked stale and cannot be ordered until refreshed. Pull-to-refresh is optional and does not repeat mutations.

## Explore

Top app bar contains back/menu as appropriate, location chip and search. Category landing shows subcategories, filters, result count, sort and optional map/list toggle when map data is available. List is default for accessibility and comparison; map is an alternate view with synchronized selected result. Filters open full-height sheet on mobile and side panel on larger screens; selected filters are removable chips. Business/service/product detail shows identity, location/service area, price model, availability freshness, policies, reviews and support.

Search results are grouped by category/type when query is global. Cards expose compare-relevant information without implying categories are directly comparable. A no-result state preserves query and offers category/area/filter alternatives. Empty catalog says service not currently available, not “search failed”.

## AI

Conversation screen: named assistant, privacy/context controls, prompt input, optional voice affordance only when speech service and permission are supported, suggestion chips, conversation history, and message provenance/actions. Responses distinguish **information**, **recommendation**, **prepared draft**, **confirmed action**. Comparison results use aligned rows for price basis, availability, ratings count and source freshness. Any paid/consequential proposal opens a review surface containing exact items/provider/beneficiary/location/time/total/cancellation terms and expiry; independent confirmation required per action. Task progress lists steps and individual state. Failed steps show retry/cancel/support; partial work remains explicit. No secret/confidential information in notification preview.

Suggested prompts are illustrative: “Find cafés nearby”, “Compare cleaning services”, “Explain my order status”. Voice is hidden when unavailable or not consented. AI task history is separate from transaction history and can be cleared under data-retention rules.

## Activity

Segmented filters: Active, Upcoming, Past. Transaction rows include type label, merchant/provider, date, amount if applicable, distinct status and next action. Order detail shows item/fulfillment timeline, address minimized, payment/refund separately, receipt, cancellation eligibility and support. Booking detail shows date/time zone, provider, beneficiary, slot, policy, reschedule/cancel. Delivery tracking uses map only if verified location updates exist; timeline remains available. Payment history links to orders/bookings and shows pending/failed/refund states; no standalone payment action that duplicates transaction.

First activity empty state explains where orders/bookings appear and returns to Explore. Loading, pagination error, offline stale and session-expired follow 14.

## Profile

Sections: personal details; address book; payment method references managed through payment provider flow; favorites; reviews; notification preferences; security/devices; privacy/consent/export/deletion; family (when enabled); language; help/support. Loyalty is reserved for future scope and must not appear until its rules and value exist. Display only own profile and explicit family shares. Password/payment/security actions may require reauthentication. Delete account states retention exceptions and progress.

## Screen behavior matrix

| Screen | Primary action / navigation | Loading, empty, error, offline behavior |
|---|---|---|
| Home | Change location, search, category, AI, activity | Skeleton; no supply with location alternative; retry; stale cache label |
| Explore/Search | Submit query, scope category, filter/sort, switch list/map | Debounced loading; no results; API retry preserves query; cached results stale |
| Category landing | Open subcategory/listing | Category skeleton; unavailable supply; retry; no transaction offline |
| Results map/list | Open result, select map pin, adjust filters | Partial results marked; map failure falls back to list; location manual entry |
| Business detail | Browse catalog, favorite, choose fulfillment | Freshness/availability; closed/unavailable state; cached read-only |
| Product detail | Select options/quantity, add to cart | Stock/price revalidate; unavailable option; offline no add-to-order |
| Service detail | Review scope/quote/availability, begin request | Estimate loading; provider unavailable; refresh quote online |
| Cart | Edit lines, address/fulfillment, checkout | Empty cart; stock/price mismatch; retry safe read; offline checkout disabled |
| Checkout/review | Select provider-backed method and confirm exact total | Payment pending/failure with query status; no duplicate submit; session recovery |
| Booking slot selection | Select date/staff/resource/slot | Slot loading/none; slot-taken refresh; offline cannot hold |
| Booking review | Confirm or reschedule | Hold expiry; payment/approval pending; current slot preserved where possible |
| Mobility request | Select pickup/dropoff/tier, request ride | Route quote unavailable; manual address; no provider state and retry |
| AI conversation | Ask, compare, prepare, review/confirm | Context loading; no history; tool error/partial results; offline read cached only if safe |
| AI task detail | Inspect steps, retry/cancel where allowed | Each step status; partial completion; task query after reconnect |
| Activity list | Filter transaction type/state | Empty first-use; paginated retry; offline visibly stale |
| Order detail/tracking | View timeline, cancel/support | Unknown state remains checking; map fallback to status list; session reauth |
| Booking detail | Reschedule/cancel/support | Current confirmed slot remains clear; provider response pending; refresh online |
| Payment/refund detail | View verified transaction and receipt | Pending reconciliation, failed refund queue, retry status query not charge |
| Profile/settings | Save preference or open protected subflow | Per-section loading; not configured state; save error retains input; offline save deferred only if noncritical |
| Address book/editor | Add/edit/select/delete | Empty manual entry; invalid/out-of-area; geocoder offline manual address |
| Payment methods | Provider-hosted add/remove/manage | No methods; provider unavailable; no raw credential form fallback |
| Family management | Invite/revoke/scope membership | No members; expired invite; authorization denial/revocation refresh |
| Support case | Submit/read reply and evidence | No cases; duplicate submission dedup; offline draft explicitly unsent |

## Responsive and accessibility behavior

Mobile uses single-column cards and five-item bottom navigation. Tablet can use split list/detail; desktop web consumer (if introduced) uses a top/side nav after separate research. Buttons remain reachable above keyboard; maps have textual alternatives; ratings/price/status are spoken as text; voice input never replaces text input.
