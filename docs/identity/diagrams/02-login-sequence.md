# Native login sequence

```mermaid
sequenceDiagram
  autonumber
  participant App as Flutter app
  participant Browser as System browser
  participant IdP as Identity provider
  participant SMS as Delivery adapter/provider
  participant API as KUNDE API
  participant DB as KUNDE identity store
  App->>App: Create state, nonce, PKCE verifier and challenge
  App->>Browser: Open authorize URL with PKCE S256
  Browser->>IdP: Authorization request
  IdP->>SMS: Send IdP-owned OTP challenge
  SMS-->>IdP: Delivery status
  IdP-->>Browser: Phone verification UI
  Browser->>IdP: Submit OTP
  IdP-->>Browser: Authorization code to exact app link
  Browser-->>App: Redirect with code and state
  App->>App: Verify state, issuer and callback; exchange with verifier
  App->>IdP: Token request
  IdP-->>App: ID token, API access token, rotating refresh token
  App->>API: API request with access token
  API->>API: Validate signature, issuer, audience and time claims
  API->>DB: Resolve issuer and subject to KUNDE user ID
  DB-->>API: Canonical principal and status
  API-->>App: Resource-authorized response
```

Sequence assumes the selected IdP supports the described native flow; confirm with POC before implementation.
