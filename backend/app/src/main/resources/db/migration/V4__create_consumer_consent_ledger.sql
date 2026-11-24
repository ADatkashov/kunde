-- TASK-007 / ADA-73. Consent ledger foundation; no legal policy is approved here.
-- No synthetic or real consent is inferred from sign-in, profile edits or account creation.
CREATE TABLE profile.consent_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purpose varchar(64) COLLATE "C" NOT NULL
        CHECK (purpose ~ '^[a-z][a-z0-9_]*$'),
    policy_version varchar(64) COLLATE "C" NOT NULL
        CHECK (length(btrim(policy_version)) > 0),
    document_sha256 varchar(64) COLLATE "C" NOT NULL
        CHECK (document_sha256 ~ '^[0-9a-f]{64}$'),
    locale varchar(2) NOT NULL CHECK (locale IN ('ru', 'kk', 'en')),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (purpose, policy_version, locale)
);
CREATE TABLE profile.consent_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES identity.users(id),
    policy_id uuid NOT NULL REFERENCES profile.consent_policies(id),
    action varchar(16) NOT NULL CHECK (action IN ('GRANTED', 'WITHDRAWN')),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT consent_events_identity UNIQUE (id, user_id)
);
CREATE INDEX consent_events_user_policy_order_idx
    ON profile.consent_events (user_id, policy_id, id DESC);
-- Intentionally no seed policies, default grants or automatic migration of
-- existing users to consented status. Approval, retention and withdrawal
-- side effects require privacy/legal ownership and an explicit API contract.
