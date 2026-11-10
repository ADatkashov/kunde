# ADR-009: Authentication and Session Model

- **Status:** Proposed for review
- **Context/problem:** PRD calls for phone registration/OTP and secure consumer/partner/provider/admin sessions.
- **Options:** Bespoke auth; standards-based OIDC-compatible identity provider; managed regional identity service.
- **Evaluation:** Bespoke implementation increases credential/session risk. OIDC externalizes protocol complexity and supports multiple clients, but vendor region/features and account recovery need review. Managed service lock-in and data location are material.
- **Decision:** Recommend OIDC/OAuth-compatible protocol and provider abstraction; OTP is challenge channel, not the whole privileged identity model. Provider remains TBD.
- **Consequences:** Short-lived tokens, refresh rotation/reuse detection, device revocation, MFA/step-up for privileged roles.
- **Risks:** Suitable provider and SMS delivery in Kazakhstan unknown; recovery/SIM-swap risk.
- **Revisit when:** Security/legal/team/vendor assessment compares in-country self-host and managed options.
