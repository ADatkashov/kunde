# Logical identity data model

```mermaid
erDiagram
  KUNDE_USER ||--o{ EXTERNAL_IDENTITY : maps
  KUNDE_USER ||--o{ CONTACT_METHOD : owns
  KUNDE_USER ||--o{ AUTH_SESSION_REF : references
  KUNDE_USER ||--o{ CONSENT_RECORD : records
  KUNDE_USER ||--o{ IDENTITY_LINK_EVENT : participates
  KUNDE_USER ||--o{ BUSINESS_MEMBERSHIP : receives

  KUNDE_USER {
    uuid user_id PK
    string status
    datetime created_at
    datetime deleted_at
  }
  EXTERNAL_IDENTITY {
    uuid identity_id PK
    uuid user_id FK
    string issuer UK
    string subject UK
    datetime linked_at
  }
  CONTACT_METHOD {
    uuid contact_id PK
    uuid user_id FK
    string kind
    string encrypted_value
    datetime verified_at
    datetime revoked_at
  }
  AUTH_SESSION_REF {
    uuid session_id PK
    uuid user_id FK
    string provider_reference
    datetime revoked_at
  }
  CONSENT_RECORD {
    uuid consent_id PK
    uuid user_id FK
    string purpose
    string notice_version
    datetime granted_at
  }
  IDENTITY_LINK_EVENT {
    uuid event_id PK
    uuid actor_user_id FK
    uuid target_user_id FK
    string outcome
    datetime occurred_at
  }
  BUSINESS_MEMBERSHIP {
    uuid membership_id PK
    uuid user_id FK
    string tenant_id
    string grant_scope
    datetime valid_until
  }
```

Logical fields only; no migration or exact SQL type/uniqueness policy is approved. Enforce exact unique `(issuer, subject)`; contact uniqueness awaits shared/recycled-number policy.
