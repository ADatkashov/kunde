-- Home Services offers: a partner's bookable service (marketplace.booking_services of a CLEANING venue) classified by a
-- catalogue definition (V60) and moderated before it becomes visible. Price, duration and slots stay in the Booking Engine.
-- Status flow: DRAFT -> PENDING (partner) -> PUBLISHED | REJECTED (staff); PUBLISHED -> SUSPENDED -> PUBLISHED (staff);
-- PENDING | PUBLISHED -> DRAFT (partner withdraws); REJECTED -> PENDING (partner resubmits). Every change is audited.
CREATE TABLE marketplace.home_service_offers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id uuid NOT NULL UNIQUE REFERENCES marketplace.booking_services(id),
    definition_code varchar(40) COLLATE "C" NOT NULL REFERENCES marketplace.home_service_definitions(code),
    -- How the booking price is read: a fixed amount, "from" an amount, or per hour / square metre / unit; a diagnostic
    -- visit or an individual quote is settled with the customer before work (no hidden surcharges).
    pricing_model varchar(16) COLLATE "C" NOT NULL
        CHECK (pricing_model IN ('FIXED', 'FROM', 'HOURLY', 'PER_SQM', 'PER_UNIT', 'DIAGNOSTIC', 'QUOTE')),
    home_visit boolean NOT NULL DEFAULT true,
    warranty_days integer NOT NULL DEFAULT 0 CHECK (warranty_days BETWEEN 0 AND 1095),
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'PENDING', 'PUBLISHED', 'REJECTED', 'SUSPENDED')),
    status_reason varchar(200),
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX home_service_offers_catalog_idx ON marketplace.home_service_offers (definition_code) WHERE status = 'PUBLISHED';
CREATE INDEX home_service_offers_status_idx ON marketplace.home_service_offers (status, updated_at);

CREATE TABLE marketplace.home_service_offer_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    offer_id uuid NOT NULL REFERENCES marketplace.home_service_offers(id),
    version bigint NOT NULL CHECK (version > 0),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    actor_role varchar(8) COLLATE "C" NOT NULL CHECK (actor_role IN ('PARTNER', 'ADMIN')),
    from_status varchar(12) COLLATE "C",
    to_status varchar(12) COLLATE "C" NOT NULL,
    reason varchar(200),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (offer_id, version)
);

CREATE TRIGGER home_service_offer_events_immutable
    BEFORE UPDATE OR DELETE ON marketplace.home_service_offer_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
