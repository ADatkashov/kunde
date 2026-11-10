# OTP delivery sequence

```mermaid
sequenceDiagram
  autonumber
  participant User
  participant App as Flutter app
  participant IdP as Identity provider
  participant Port as OTP delivery port
  participant Vendor as SMS vendor
  User->>App: Enter phone and start sign-in
  App->>IdP: OIDC authorization request
  IdP->>IdP: Normalize, rate-limit, create expiring challenge
  IdP->>Port: Send challenge message with opaque attempt ID
  Port->>Vendor: HTTPS request with vendor credentials
  Vendor-->>Port: Accepted or failed plus message reference
  Port-->>IdP: Status mapped to normalized outcome
  IdP-->>App: Generic challenge UI/result
  User->>App: Enter code
  App->>IdP: Submit challenge proof
  IdP->>IdP: Check expiry, attempt limit and one-time use
  IdP-->>App: Continue OIDC flow or generic failure
  Vendor-->>Port: Optional delivery report
  Port->>Port: Validate callback and emit redacted status
```

Delivery status is not authentication proof. If the provider's API generates and verifies its own OTP, this sequence requires a supported IdP extension and a separate lock-in review.
