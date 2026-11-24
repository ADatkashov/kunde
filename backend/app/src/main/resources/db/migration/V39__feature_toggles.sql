-- Runtime switches managed from the admin application. The environment variable of a feature stays the safety ceiling
-- (a feature is only ever on when the environment allows it AND no administrator switched it off), so a missing row means
-- "follow the environment" and existing deployments keep their behaviour.
CREATE TABLE identity.feature_toggles (
    feature varchar(20) PRIMARY KEY CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY')),
    enabled boolean NOT NULL,
    version bigint NOT NULL DEFAULT 1,
    reason varchar(200) NOT NULL,
    updated_by uuid NOT NULL REFERENCES identity.users(id),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Append-only journal of every switch: who, when, from what to what and why.
CREATE TABLE identity.feature_toggle_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    feature varchar(20) NOT NULL CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY')),
    admin_user_id uuid NOT NULL REFERENCES identity.users(id),
    previous_enabled boolean,
    new_enabled boolean NOT NULL,
    reason varchar(200) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER feature_toggle_events_immutable BEFORE UPDATE OR DELETE ON identity.feature_toggle_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
