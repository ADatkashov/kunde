# 02 — User Personas and Roles

Roles are capabilities, not trust levels. Access is scoped to a user, family, business, assigned task, case, or explicit platform duty. Authentication does not imply authorization. See `13-permissions-and-access-control.md`.

| Role | Goals and permitted work | Boundary |
|---|---|---|
| Guest | Browse public categories and eligible public listings; start registration | No personal, family, transaction, or private partner data |
| Consumer | Manage own profile, addresses, preferences; discover, order/book, pay, review, request support | Own records only; payment instruments are tokenized by provider |
| Family owner | Create family group, invite/revoke members, manage own and delegated settings, book for a member where permission allows | No automatic access to adult member's private history, payment methods, health details, or messages |
| Family member | Use own profile and explicitly shared family resources | Cannot administer group unless delegated; child data visible only to authorized guardian and necessary operators |
| Business owner | Manage verified business, locations, catalog, staff roles, availability and business transaction operations | Only owned/verified business scope; no unrelated customer data or raw payment credentials |
| Business manager | Operate assigned locations/catalog/orders/bookings according to grants | No ownership transfer, payout destination or sensitive settings unless explicitly granted |
| Business employee | Process assigned orders/bookings and service tasks | Minimum fields needed for assigned work; no unrelated customers, finance reports or bulk export |
| Driver | Receive eligible transport assignments and update assigned trip | Only trip information needed for fulfillment; customer address/contact access is time-bounded |
| Courier | Receive eligible delivery tasks and update pickup/dropoff | Only assigned delivery data; no catalog, unrelated order, or finance access |
| Independent service provider | Manage own profile/availability and assigned service work | Own provider scope and assigned customer/job only |
| Support agent | Search by approved identifiers, view minimal transaction timeline, manage cases and approved resolutions | No arbitrary account browsing, credential access, or discretionary financial override |
| Moderator | Review reported listings/reviews/content and apply policy actions | No payment credentials or unrelated private conversation access |
| Finance operator | Reconcile payments, refunds, commissions and settlements | Financial operations scope; sensitive customer details masked unless necessary for a case |
| Platform administrator | Configure platform operations and role grants under audited, least-privilege controls | No implicit access to all user content; privileged access is justified, scoped and logged |
| Super administrator | Break-glass platform control, security recovery and top-level access governance | Strong authentication, reason, time-bound elevation, immutable audit and post-use review |

## Personas and primary journeys

- **Busy consumer:** search nearby, compare price/availability, place a food order, track it, resolve a missing item.
- **Family coordinator:** book a child's class using guardian authorization, share schedule details without exposing adult account data.
- **Local merchant:** publish accurate menu and availability, accept/reject within configured response window, fulfill and reconcile.
- **On-demand worker:** receive a scoped assignment, accept it, update status and report an incident.
- **Support operator:** identify a failed transaction, explain verified state, route refund/dispute with evidence.
- **Trust operator:** investigate reported content or suspicious activity with constrained data access.

## Story index

Detailed role-linked stories and testable outcomes are in `03-user-stories.md` and `07-acceptance-criteria.md`. Role grants must be denied by default and re-evaluated on every sensitive request, including API and AI tool calls.
