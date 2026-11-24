-- ADR-018 step 2: append-only audit of partner profile changes (who renamed which partner, from what to what).
-- The business display name is not personal data of an individual; no other profile fields exist yet.
CREATE TABLE marketplace.partner_profile_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    event_type varchar(16) COLLATE "C" NOT NULL CHECK (event_type IN ('RENAMED')),
    old_value varchar(120) NOT NULL,
    new_value varchar(120) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX partner_profile_events_partner_idx ON marketplace.partner_profile_events (partner_id, id);
CREATE TRIGGER partner_profile_events_immutable BEFORE UPDATE OR DELETE ON marketplace.partner_profile_events
    FOR EACH ROW EXECUTE FUNCTION marketplace.reject_audit_mutation();
