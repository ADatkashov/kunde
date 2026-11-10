# 10 — Provider and Driver Application

Provider app adapts task vocabulary to role (driver, courier, home-service professional, appointment practitioner). Do not expose irrelevant tabs or requests. One-handed operation, outdoor readability, explicit assignment and safety are priorities. Service category workflow determines which steps exist.

## Navigation and screen set

| Screen group | Driver | Courier | Independent service provider |
|---|---|---|---|
| Registration/eligibility | Identity, vehicle/license checks as required | Identity and delivery eligibility | Identity, skill/credential verification as required |
| Availability | Online/offline, eligible area, service tier | Availability, delivery radius | Working hours, service area and bookable resources |
| Incoming assignment | Pickup, drop-off, fare basis, distance/expiry | Pickup, package essentials, destination area/expiry | Customer area, service scope, duration/quote/expiry |
| Active task | Pickup/navigation, arrive, start trip, complete | Pickup scan/confirmation, route, dropoff evidence | Visit/appointment details, accept, arrive, start, complete/quote |
| Earnings/history | Trips and payout status if enabled | Deliveries and payout status if enabled | Jobs and payout status if enabled |

## Core flow

Sign in → verify eligible role/device → set availability → receive clear assignment offer with expiry and compensation terms if policy permits → accept/reject → task instructions → state-specific progress actions → completion evidence → earnings/history/support. Decline is allowed and nonpunitive unless contract explicitly defines eligibility; UI must not imply a rejected assignment is completed. If no accept/reject response by expiry, offer disappears with reason/status.

## Interaction and safety

- Bottom primary action remains within thumb zone and uses explicit verbs (“Accept request”, “Arrived”, “Picked up”, “Complete delivery”). Destructive/no-show actions require reason.
- Do not require device interaction while driving; use safe, legally reviewed interaction states and voice/navigation handoff only if supported.
- Show only name/contact/location data needed for active task; masking/controlled call/chat when available. Remove customer details after assignment ends.
- Address and route remain available as text; map/network loss has call/support/incident fallback without fabricated GPS.
- Offline status updates queue with original task/version and reconcile; show queued vs confirmed. Assignment revocation blocks stale completion.
- Documents use secure upload, expiry reminders and reviewed status; no unnecessary admin data exposure.

## States

Availability: offline, setting online, online, paused, ineligible. Offer: new, expiring countdown, accepted, declined, expired, withdrawn. Task: assigned, en route, arrived, picked up/started, in progress, delivered/completed, incident, cancelled. Payment/earnings remain separate, verified and potentially delayed. Each status has text + icon and accessibility announcement.

## Responsive/accessibility

Mobile portrait is primary; large touch targets ≥48 px and high-contrast controls. Tablets may show task list/detail split. Dynamic text must not hide safety details. Outdoor mode can increase contrast and font size but does not alter transaction status semantics. Review [`wireframes/provider-home.md`](wireframes/provider-home.md).
