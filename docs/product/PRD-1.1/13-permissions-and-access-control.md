# 13 — Permissions and Access Control

## Policy model

Combine role-based permissions with resource attributes: principal, tenant/business/family, assigned transaction, purpose, data classification, transaction state and time. Deny by default. Check authorization on every server request and AI tool call; hiding UI controls is not enforcement.

| Resource/action | Guest | Consumer | Family owner/member | Partner staff | Driver/provider | Support | Moderator | Finance | Admin/super admin |
|---|---|---|---|---|---|---|---|---|---|
| Public listing | Read public | Read | Read | Own scoped listing | Own public profile | Case need only | Reported content | No default | Config scope |
| Profile/address | None | Own | Own; explicitly shared subset | None | Assigned job minimum only | Case purpose, masked | None | Masked if reconciliation needs | No implicit browse |
| Order/booking | None | Own/authorized beneficiary | Only delegated family records | Assigned business transaction | Assigned task subset | Assigned case | None | Linked financial fields | Scoped audited operation |
| Payment credential | None | Provider token reference/manage | No inherited access | None | None | None | None | Token/reference only | None |
| Payment/refund state | None | Own linked status | Delegated transaction only | Own transaction status as needed | No payment details | Explain/read; limited action | None | Reconcile/operate by grant | Audited scoped grant |
| Family membership | None | Own membership | Owner manages grants; member sees own | None | None | Case-only minimum | None | None | Exceptional audited access |
| Catalog/availability | None | Read | Read | Business/location grant | Own availability | Case only | Moderate report | None | Platform configuration |
| Audit/security log | None | Own security activity | Own security activity | Own business actions | Own task actions | Case-linked subset | Moderation case | Finance scope | Security/admin scope |

## Role boundaries

- Consumer acts only for self or an explicitly authorized beneficiary. Consent and actor are separately recorded.
- Family owner does not automatically read another adult member's private transaction history, health data or payment instruments. Guardianship/delegation must be documented and revocable.
- Business owner/manager/employee grants are scoped to verified business and assigned locations/actions. Payout settings and ownership transfer require stronger authorization than routine order processing.
- Driver, courier and provider access is limited to currently assigned work and expires when assignment ends; contact/address information is minimized.
- Support requires case assignment and reason. Finance handles ledger and settlement; moderation handles content. Separation prevents one role from silently changing both evidence and money.
- Admin configuration access does not imply unrestricted customer-content access. Super-admin break-glass requires reason, strong authentication, expiry and independent review.

## Required controls

- Authentication, MFA/step-up for privileged and financial actions, session revocation, least privilege, scoped tokens, audit, rate limits and access review.
- Sensitive fields are masked by default. Bulk export is separately granted and audited.
- Revocation takes effect on next authorization decision; invalidate cached grants/session tokens as soon as practical.
- AI tool permissions are identical to user/API permissions and bound to conversation user. Model-generated arguments are untrusted input.
- Emergency access is time-limited and cannot bypass immutable financial records or state-machine validation.

Denied actions return a non-revealing authorization response; security log includes actor, scope, action, resource identifier and correlation ID without leaking protected data.
