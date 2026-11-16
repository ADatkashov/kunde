-- Partner Operations MVP (DEV pilot): a partner (marketplace.partners, V8) manages incoming Food/Grocery orders and
-- bookings of its own restaurant/venue. Ownership is a nullable link: rows without a partner keep the existing DEV
-- simulation (Food) and instant DEV-mock confirmation (Booking), so older flows are unchanged.
ALTER TABLE marketplace.food_restaurants ADD COLUMN partner_id uuid REFERENCES marketplace.partners(id);
CREATE INDEX food_restaurants_partner_idx ON marketplace.food_restaurants (partner_id) WHERE partner_id IS NOT NULL;
ALTER TABLE marketplace.booking_venues ADD COLUMN partner_id uuid REFERENCES marketplace.partners(id);
CREATE INDEX booking_venues_partner_idx ON marketplace.booking_venues (partner_id) WHERE partner_id IS NOT NULL;

-- Food: PARTNER orders are moved only by the partner (no elapsed-time simulation).
ALTER TABLE transactions.food_orders
    ADD COLUMN fulfillment_mode varchar(12) COLLATE "C" NOT NULL DEFAULT 'SIMULATED'
        CHECK (fulfillment_mode IN ('SIMULATED', 'PARTNER')),
    ADD COLUMN partner_id uuid REFERENCES marketplace.partners(id),
    ADD COLUMN cancel_reason varchar(300),
    ADD COLUMN cancelled_by varchar(12) COLLATE "C" CHECK (cancelled_by IN ('CUSTOMER', 'PARTNER', 'SYSTEM')),
    ADD CONSTRAINT food_orders_partner_mode CHECK ((fulfillment_mode = 'PARTNER') = (partner_id IS NOT NULL));
CREATE INDEX food_orders_partner_idx ON transactions.food_orders (partner_id, status, placed_at DESC) WHERE partner_id IS NOT NULL;
UPDATE transactions.food_orders SET cancelled_by = 'CUSTOMER' WHERE status = 'CANCELLED';

ALTER TABLE transactions.food_order_events
    ADD COLUMN actor_type varchar(12) COLLATE "C" CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'SYSTEM')),
    ADD COLUMN actor_user_id uuid REFERENCES identity.users(id),
    ADD COLUMN reason varchar(300);

-- Booking: a venue with a partner creates PENDING requests that hold the slot until the partner decides.
ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_master_no_overlap;
ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_status_check;
ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_confirmation_check;
ALTER TABLE transactions.bookings
    ADD CONSTRAINT bookings_status_check CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED')),
    ADD CONSTRAINT bookings_confirmation_check CHECK (confirmation IN ('DEV_MOCK', 'PARTNER')),
    ADD COLUMN cancelled_by varchar(12) COLLATE "C" CHECK (cancelled_by IN ('CUSTOMER', 'PARTNER', 'SYSTEM')),
    ADD COLUMN cancel_reason varchar(300),
    ADD CONSTRAINT bookings_master_no_overlap EXCLUDE USING gist (
        master_id WITH =, tstzrange(starts_at, ends_at) WITH &&) WHERE (status IN ('PENDING', 'CONFIRMED', 'COMPLETED'));
CREATE INDEX bookings_venue_idx ON transactions.bookings (venue_id, starts_at DESC);
UPDATE transactions.bookings SET cancelled_by = 'CUSTOMER' WHERE status = 'CANCELLED';

CREATE TABLE transactions.booking_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id uuid NOT NULL REFERENCES transactions.bookings(id),
    status varchar(16) COLLATE "C" NOT NULL CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED')),
    actor_type varchar(12) COLLATE "C" NOT NULL CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'SYSTEM')),
    actor_user_id uuid REFERENCES identity.users(id),
    reason varchar(300),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX booking_events_booking_idx ON transactions.booking_events (booking_id, id);
CREATE TRIGGER booking_events_immutable BEFORE UPDATE OR DELETE ON transactions.booking_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
-- History of bookings that existed before partner operations.
INSERT INTO transactions.booking_events (booking_id, status, actor_type, actor_user_id, occurred_at)
    SELECT id, 'CONFIRMED', 'SYSTEM', NULL, created_at FROM transactions.bookings;
INSERT INTO transactions.booking_events (booking_id, status, actor_type, actor_user_id, occurred_at)
    SELECT id, 'CANCELLED', 'CUSTOMER', user_id, cancelled_at FROM transactions.bookings WHERE status = 'CANCELLED';

-- Append-only audit of partner catalog/availability/schedule changes.
CREATE TABLE marketplace.partner_catalog_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    entity_type varchar(24) COLLATE "C" NOT NULL,
    entity_id uuid NOT NULL,
    field varchar(32) COLLATE "C" NOT NULL,
    old_value varchar(300),
    new_value varchar(300),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX partner_catalog_events_partner_idx ON marketplace.partner_catalog_events (partner_id, id);
CREATE TRIGGER partner_catalog_events_immutable BEFORE UPDATE OR DELETE ON marketplace.partner_catalog_events
    FOR EACH ROW EXECUTE FUNCTION marketplace.reject_audit_mutation();
