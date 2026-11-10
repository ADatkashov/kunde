# System context

```mermaid
flowchart LR
  consumer[Consumer App]
  partner[Partner App]
  provider[Provider App]
  admin[Admin Portal]
  idp[OIDC Identity Provider]
  delivery[OTP Delivery Port]
  sms[Approved SMS or messaging vendor]
  api[KUNDE Spring API]
  identity[KUNDE Identity domain]
  authz[Business authorization domains]
  db[(KUNDE PostgreSQL)]

  consumer -->|OIDC PKCE| idp
  partner -->|OIDC PKCE| idp
  provider -->|OIDC PKCE| idp
  admin -->|strong MFA OIDC| idp
  idp --> delivery
  delivery --> sms
  consumer -->|API access token| api
  partner -->|API access token| api
  provider -->|API access token| api
  admin -->|API access token| api
  api --> identity
  api --> authz
  identity --> db
  authz --> db
  api -. validates issuer, audience, signature .-> idp
```

Dashed relation is metadata/JWKS trust and validation, not user authentication bypass. The diagram omits databases owned by an eventual IdP deployment because deployment model is undecided.
