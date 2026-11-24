-- ADR-018 (accepted 2026-11-15): KUNDE Administrator identity. A user gets the `kunde.admin` token scope only while an
-- unrevoked row exists here. Rows are never created by a public endpoint, OTP login or onboarding request: DEV admins are
-- provisioned out of band by the owner (synthetic accounts only); production adds step-up/dual control (D-14 gate).
CREATE TABLE identity.admin_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    permission varchar(32) COLLATE "C" NOT NULL CHECK (permission IN ('PARTNER_VERIFICATION', 'ADMIN_GRANTS')),
    granted_by_user_id uuid REFERENCES identity.users(id),
    reason varchar(200) NOT NULL CHECK (length(btrim(reason)) > 0),
    granted_at timestamptz NOT NULL DEFAULT now(),
    revoked_by_user_id uuid REFERENCES identity.users(id),
    revoked_at timestamptz,
    CHECK ((revoked_at IS NULL) = (revoked_by_user_id IS NULL))
);
CREATE UNIQUE INDEX admin_grants_active_uq ON identity.admin_grants (user_id, permission) WHERE revoked_at IS NULL;
CREATE INDEX admin_grants_user_idx ON identity.admin_grants (user_id) WHERE revoked_at IS NULL;
