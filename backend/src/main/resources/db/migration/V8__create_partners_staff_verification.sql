-- TASK-015 / D-07 (approved 2026-11-13): partner record, individually attributable staff roles and the
-- auditable verification state. Persistence foundation only: no HTTP API, no catalog/offering link, no
-- documents or KYC evidence (identity-proofing method, documents and retention are unapproved) and no
-- effect on ADR-014 gates (an APPROVED partner enables nothing by itself).
CREATE TABLE marketplace.partners (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name varchar(120) NOT NULL CHECK (length(btrim(display_name)) > 0),
    -- Mirrors kz.kunde.partner.PartnerVerification.Status (PB-01/PB-02 draft playbooks).
    verification_status varchar(32) COLLATE "C" NOT NULL DEFAULT 'PENDING_REVIEW'
        CHECK (verification_status IN ('PENDING_REVIEW', 'INFO_REQUESTED', 'APPROVED', 'LIMITED', 'SUSPENDED', 'REJECTED')),
    -- The applicant: the only actor who may resubmit; reviewers must not be this user.
    created_by_user_id uuid NOT NULL REFERENCES identity.users(id),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX partners_status_idx ON marketplace.partners (verification_status, created_at, id);

-- One row per (partner, person): every staff member has an individual identity; access is revocable.
CREATE TABLE marketplace.partner_staff (
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    role varchar(16) COLLATE "C" NOT NULL CHECK (role IN ('OWNER', 'MANAGER', 'OPERATOR')),
    status varchar(16) COLLATE "C" NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED')),
    granted_by_user_id uuid NOT NULL REFERENCES identity.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    revoked_by_user_id uuid REFERENCES identity.users(id),
    revoked_at timestamptz,
    PRIMARY KEY (partner_id, user_id),
    CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL AND revoked_by_user_id IS NOT NULL))
);
CREATE INDEX partner_staff_user_idx ON marketplace.partner_staff (user_id, status);

-- Append-only audit of staff changes.
CREATE TABLE marketplace.partner_staff_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    subject_user_id uuid NOT NULL REFERENCES identity.users(id),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    event_type varchar(16) COLLATE "C" NOT NULL CHECK (event_type IN ('GRANTED', 'REVOKED')),
    role varchar(16) COLLATE "C" NOT NULL CHECK (role IN ('OWNER', 'MANAGER', 'OPERATOR')),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX partner_staff_events_partner_idx ON marketplace.partner_staff_events (partner_id, id);

-- Append-only verification history (immutable audit entry of PartnerVerification).
CREATE TABLE marketplace.partner_verification_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    decision varchar(16) COLLATE "C" NOT NULL
        CHECK (decision IN ('SUBMIT', 'REQUEST_INFO', 'RESUBMIT', 'APPROVE', 'REJECT', 'LIMIT', 'SUSPEND', 'RESTORE')),
    from_status varchar(32) COLLATE "C"
        CHECK (from_status IN ('PENDING_REVIEW', 'INFO_REQUESTED', 'APPROVED', 'LIMITED', 'SUSPENDED', 'REJECTED')),
    to_status varchar(32) COLLATE "C" NOT NULL
        CHECK (to_status IN ('PENDING_REVIEW', 'INFO_REQUESTED', 'APPROVED', 'LIMITED', 'SUSPENDED', 'REJECTED')),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    reason text CHECK (reason IS NULL OR (length(btrim(reason)) > 0 AND length(reason) <= 2000)),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((decision = 'SUBMIT') = (from_status IS NULL)),
    CHECK (decision NOT IN ('REQUEST_INFO', 'REJECT', 'LIMIT', 'SUSPEND') OR reason IS NOT NULL)
);
CREATE INDEX partner_verification_events_partner_idx ON marketplace.partner_verification_events (partner_id, id);

-- Audit tables are immutable: the application never updates or deletes rows, and the database enforces it.
CREATE FUNCTION marketplace.reject_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'integrity_constraint_violation';
END;
$$;
CREATE TRIGGER partner_staff_events_immutable BEFORE UPDATE OR DELETE ON marketplace.partner_staff_events
    FOR EACH ROW EXECUTE FUNCTION marketplace.reject_audit_mutation();
CREATE TRIGGER partner_verification_events_immutable BEFORE UPDATE OR DELETE ON marketplace.partner_verification_events
    FOR EACH ROW EXECUTE FUNCTION marketplace.reject_audit_mutation();
