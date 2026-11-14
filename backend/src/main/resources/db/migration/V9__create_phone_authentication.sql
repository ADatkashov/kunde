-- Phone OTP authentication (ADR-015 amended 2026-11-14). Only hashes of OTP codes and refresh tokens are stored.
-- phone_e164 is personal data: DEV holds synthetic numbers only; production needs the privacy/residency gates.
CREATE TABLE identity.phone_identities (
    user_id uuid PRIMARY KEY REFERENCES identity.users(id),
    phone_e164 varchar(16) COLLATE "C" NOT NULL UNIQUE CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_login_at timestamptz
);
CREATE TABLE identity.otp_challenges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 varchar(16) COLLATE "C" NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    code_hash char(64) NOT NULL,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz
);
CREATE INDEX otp_challenges_phone_idx ON identity.otp_challenges (phone_e164, created_at DESC);
CREATE TABLE identity.auth_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    revoke_reason varchar(24) CHECK (revoke_reason IN ('LOGOUT', 'REFRESH_REPLAY', 'ADMIN'))
);
CREATE INDEX auth_sessions_user_idx ON identity.auth_sessions (user_id);
CREATE TABLE identity.refresh_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES identity.auth_sessions(id),
    token_hash char(64) NOT NULL UNIQUE,
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz
);
CREATE INDEX refresh_tokens_session_idx ON identity.refresh_tokens (session_id);
-- Audit trail without raw phone numbers: phone_hash is a keyed hash, never the number.
CREATE TABLE identity.auth_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_type varchar(24) NOT NULL CHECK (event_type IN (
        'OTP_REQUESTED', 'OTP_THROTTLED', 'OTP_DELIVERY_FAILED', 'OTP_VERIFIED', 'OTP_FAILED', 'OTP_LOCKED',
        'SESSION_STARTED', 'TOKEN_REFRESHED', 'REFRESH_REPLAY', 'LOGOUT')),
    user_id uuid REFERENCES identity.users(id),
    phone_hash char(64),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_events_phone_idx ON identity.auth_events (phone_hash, occurred_at DESC);
