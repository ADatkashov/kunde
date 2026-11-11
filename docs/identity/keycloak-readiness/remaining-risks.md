# Remaining risks

- Browser logout, explicit refresh revocation and admin session deletion can leave already-issued JWTs accepted by an offline resource server. Define and test the revocation SLO for suspension, lost devices and sensitive actions.
- Clock tolerance adds to the access window. Time synchronization, explicit timestamp policy and alerting require an environment drill.
- A lost refresh response can leave a device holding the consumed refresh token. Design atomic storage, one refresh in flight and a recoverable reauthentication path.
- Key overlap must cover deployed JWT, refresh and client/session semantics. Test emergency key removal, cached JWKS behavior and fleet convergence separately from routine rotation.
- Provider client scope and role mappings do not replace KUNDE domain permissions. Principal mapping, restricted/deleted account enforcement, token/client profile validation, callback and device compromise still need implementation review.
- Multi-node concurrency, capacity, backup and restore, migration, audit retention, admin MFA and incident ownership remain release gates.
- Kazakhstan legal review, telecom/OTP evidence and procurement remain open. No live personal data entered the drill.
