-- ADR-018 step 3: append-only audit of partner offering changes. Records who did what to which offering, not the content.
CREATE TABLE marketplace.offering_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    offering_id uuid NOT NULL REFERENCES marketplace.offerings(id),
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    event_type varchar(16) COLLATE "C" NOT NULL CHECK (event_type IN ('CREATED', 'UPDATED', 'PUBLISHED', 'UNPUBLISHED')),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX offering_events_offering_idx ON marketplace.offering_events (offering_id, id);
CREATE TRIGGER offering_events_immutable BEFORE UPDATE OR DELETE ON marketplace.offering_events
    FOR EACH ROW EXECUTE FUNCTION marketplace.reject_audit_mutation();
