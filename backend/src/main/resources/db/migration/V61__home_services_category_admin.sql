ALTER TABLE marketplace.home_service_categories
    ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK (version > 0);

ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS',
     'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS', 'FOOD_OPERATIONS', 'EDUCATION_OPERATIONS',
     'GROCERIES_OPERATIONS', 'EVENTS_OPERATIONS', 'HOME_SERVICES_CATALOG'));

CREATE TABLE marketplace.home_service_category_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_code varchar(32) COLLATE "C" NOT NULL REFERENCES marketplace.home_service_categories(code),
    version bigint NOT NULL CHECK (version > 0),
    admin_user_id uuid NOT NULL REFERENCES identity.users(id),
    reason varchar(200) NOT NULL CHECK (length(btrim(reason)) >= 3),
    previous_state jsonb,
    new_state jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (category_code, version)
);

CREATE TRIGGER home_service_category_events_immutable
    BEFORE UPDATE OR DELETE ON marketplace.home_service_category_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
