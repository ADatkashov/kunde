# 06 — Order Fulfillment Operations

The Order aggregate is the customer’s goods/fulfillment request; Booking and Payment are separate linked records. All operational times/deadlines are category/contract configured and remain TBD until partner pilot. See PRD 1.1 §09 and Architecture 15.

## Fulfillment models

| Model | Who accepts/prepares/fulfills | KUNDE responsibility | When appropriate / key control |
|---|---|---|---|
| Partner fulfillment | Merchant accepts, prepares and hands over | Route order, provide status/support, reconcile | Restaurant pickup or merchant-delivered goods; partner response SLA |
| Partner + courier | Merchant prepares; partner/KUNDE/3PL courier delivers | Dispatch only if contracted, track statuses, exceptions | Food/grocery where operator exists; seller and carrier role disclosed |
| KUNDE-managed fulfillment | KUNDE contracts/coordinates provider capacity | Dispatch, customer service, safety and cost control under model | Only after staffing/contracts/insurance/authorization exist; not assumed |
| On-demand provider | Qualified provider accepts service assignment | Match, scope confirmation, payment coordination, dispute routing | Home/auto service with quote and provider capacity |
| Scheduled fulfillment | Partner/provider commits to future slot | Hold capacity, reminders, change/late handling | Appointment, class, event or scheduled delivery |
| Third-party logistics | Independent contracted carrier executes | Validate integration, status evidence, customer escalation | Demand outside own/partner coverage; vendor performance measured |

## Common transaction operations

1. Validate partner active, service area, catalog version, quote/inventory, fulfillment mode, address/time and policy.
2. Present exact total and terms; consumer confirms with idempotency token.
3. Create order/payment attempt; payment status remains pending until provider verified.
4. Route to authorized partner/provider; start response timer. Partner accepts, rejects with reason, or times out. Do not quietly treat timeout as acceptance.
5. On acceptance, expose status and customer-safe instructions. Changes to price, scope, address or fulfillment require user review where material.
6. Track category-specific states; record actor/source/time for each transition.
7. Confirm completion via the appropriate evidence (handoff, delivery code/receipt, provider completion, event admission); do not require app-side proof if the operating model cannot supply it—use explicitly approved evidence alternatives.
8. Reconcile payment, commission, refund and partner/provider payable independently; allow support to inspect a joined timeline.

## Category playbooks

- **Food/grocery:** merchant checks availability, accepts/rejects, prepares; substitutions are user-approved only; merchant/courier records ready, pickup and delivered. Missing/incorrect item case supports line-level resolution.
- **Retail:** stock/variant and pickup/delivery revalidated; partner packs; returns/warranty follow product/partner/legal policy.
- **Mobility:** quote/request → provider dispatch/accept → pickup → trip → completion; no-provider timeout and safety incident route.
- **Home/auto:** service request → inspection/quote if required → user accepts final scope/price → provider visit/work → completion/evidence → dispute path.
- **Care/health/education:** booking lifecycle governs capacity, confirmation, check-in, completion/no-show; not an order-preparation timeline.
- **Experiences:** inventory hold → payment → verified ticket issuance; an accepted payment without ticket is a failed fulfillment exception.

## Exceptions and ownership

Partner rejection: route to alternative only if user accepts materially different provider/price/time; otherwise cancel and compensate. No provider: reassign only inside confirmed preference/policy window, then cancel/escalate. Partner/provider disconnect after acceptance: preserve last verified state, contact via operations channel, mark “checking,” escalate by timer. Late work: notify user with verified estimate and options. Failed fulfillment: capture reason/evidence; release/return inventory; void/refund; support owner; partner quality signal. Manual overrides use a privileged role, reason and immutable audit.
