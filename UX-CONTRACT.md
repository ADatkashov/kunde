# KUNDE mobile interaction contract

| Capability | Owner | Behavior and source | Verification |
|---|---|---|---|
| Authentication | AuthRepository / AppAuthGateway | ADR-015: system-browser code + PKCE, secure vault, serialized refresh/logout; no automatic contact linking | auth_repository_test.dart; auth_gateway_test.dart |
| Protected navigation | AuthScreen | Load /me before home; clear protected profile and in-memory draft on logout/401; reauthenticate explicitly | auth_screen_test.dart |
| Form | Material Form / TextFormField | ConsumerIdentityController validation, explicit save; no duplicate submit; keep draft on network failure | auth_screen_test.dart |
| Language | Material PopupMenuButton / ChoiceChip | RU/KK/EN; local welcome selection, profile preference committed only on save | auth_screen_test.dart |
| Feedback | AuthScreen semantic live region | Loading indicator, inline failure/retry, save success, partial provider logout warning | auth_screen_test.dart |
| CRUD | /me API and AuthScreen | Own profile only; version required; 409 preserves draft and requires explicit reload; cancellation/route changes ask to discard dirty edits | ConsumerIdentityIntegrationTest; auth_screen_test.dart |
| Scrollbar | Flutter Material ScrollBehavior | Platform-owned scrolling and scrollbars; safe areas and keyboard resizing | widget layout checks |

No billing, deletion, phone verification, legal consent or session administration
UI is introduced. Production readiness gates in ADR-015 remain separate from
development authorization. Test doubles exist only under mobile/test.
