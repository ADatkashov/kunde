CREATE TABLE identity.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RESTRICTED', 'DELETED')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE identity.external_bindings (
    issuer varchar(512) COLLATE "C" NOT NULL CHECK (length(issuer) > 0),
    subject varchar(255) COLLATE "C" NOT NULL CHECK (length(subject) > 0),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (issuer, subject)
);
CREATE INDEX external_bindings_user_idx ON identity.external_bindings (user_id);
CREATE TABLE profile.consumer_profiles (
    user_id uuid PRIMARY KEY REFERENCES identity.users(id),
    display_name varchar(80),
    preferred_language varchar(2) CHECK (preferred_language IN ('ru', 'kk', 'en')),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0)
);
CREATE TABLE identity.account_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES identity.users(id),
    event_type varchar(32) NOT NULL CHECK (event_type IN ('PROVISIONED', 'PROFILE_UPDATED')),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX account_events_user_idx ON identity.account_events (user_id, id);
