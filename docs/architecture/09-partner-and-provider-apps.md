# 09 — Partner and Provider Applications

The PRD defines partner, driver/provider surfaces; a separate native app is not mandated. Start with a responsive authenticated web console for partner/admin workflows unless operational research proves mobile-only requirements; provider workflow may use a Flutter role-specific app or shared client shell, but never assume a consumer app account grants work access.

## Partner capabilities

Business owner onboarding/verification; location and service-area setup; category/catalog editing; price and schedule management; role invitations; request queue; accept/reject/update with deadlines; incident/support; finance/settlement view only after approved. Business tenant and location are mandatory authorization attributes. Payout destination and owner changes require step-up verification and audited review.

## Provider capabilities

Eligibility and document review; availability; assignment offer/expiry; accept/reject; assigned task details; status transitions; navigation handoff; incident reporting; earnings only if payout process is live. Assignment payload contains minimal user contact/location, expires on completion/revocation and supports offline-safe status queue with conflict resolution.

## Authentication and devices

Use distinct principal role grants and tenant scopes, strong auth for privileged business operations, device/session revocation and notification of account changes. Shared identity can support multiple roles through explicit grants; role switch is visible and API scopes remain server-checked.

## Integration and delivery

Partner webhooks use signed credentials, timestamp window, event ID dedupe and replay protection. Polling is fallback only where partner capability allows. Offline updates are commands with original actor/time and expected version, not direct state overwrite. Partner/provider outages trigger customer-visible recovery and support queues. Screens/data roles are in PRD 1.1 §08.
