ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS'));

CREATE TABLE transactions.delivery_couriers (
    user_id uuid PRIMARY KEY REFERENCES identity.users(id),
    display_name varchar(80) NOT NULL,
    vehicle varchar(12) NOT NULL CHECK (vehicle IN ('WALK', 'BICYCLE', 'MOTORCYCLE', 'CAR')),
    status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'BLOCKED')),
    online boolean NOT NULL DEFAULT false CHECK (NOT online OR status = 'APPROVED'),
    max_grams integer CHECK (max_grams BETWEEN 1 AND 50000),
    max_side_cm integer CHECK (max_side_cm BETWEEN 1 AND 200),
    latitude numeric(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9,6) CHECK (longitude BETWEEN -180 AND 180),
    observed_at timestamptz,
    CHECK (status <> 'APPROVED' OR (max_grams IS NOT NULL AND max_side_cm IS NOT NULL)),
    CHECK (num_nonnulls(latitude, longitude, observed_at) IN (0, 3)),
    CHECK (online OR observed_at IS NULL)
);

CREATE TABLE transactions.delivery_courier_reviews (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    courier_id uuid NOT NULL REFERENCES transactions.delivery_couriers(user_id),
    reviewer_id uuid NOT NULL REFERENCES identity.users(id),
    decision varchar(12) NOT NULL CHECK (decision IN ('APPROVED', 'BLOCKED')),
    reason varchar(200) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    CHECK (courier_id <> reviewer_id)
);

CREATE TRIGGER delivery_courier_reviews_immutable BEFORE UPDATE OR DELETE ON transactions.delivery_courier_reviews
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_delivery_event_mutation();

CREATE TYPE transactions.delivery_state AS ENUM (
    'CREATED', 'SEARCHING_COURIER', 'COURIER_ASSIGNED', 'COURIER_ARRIVING', 'COURIER_ARRIVED',
    'PICKED_UP', 'IN_TRANSIT', 'DELIVERED', 'COMPLETED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_COURIER',
    'CANCELLED_BY_SYSTEM', 'NO_COURIER_AVAILABLE', 'PICKUP_FAILED', 'DELIVERY_FAILED',
    'RETURN_REQUESTED', 'RETURNING', 'RETURNED_TO_SENDER', 'DISPUTED'
);

ALTER TABLE transactions.deliveries DROP CONSTRAINT deliveries_status_check;
ALTER TABLE transactions.deliveries ALTER COLUMN status TYPE transactions.delivery_state
    USING status::transactions.delivery_state;
ALTER TABLE transactions.delivery_events DROP CONSTRAINT delivery_events_status_check;
ALTER TABLE transactions.delivery_events ALTER COLUMN status TYPE transactions.delivery_state
    USING status::transactions.delivery_state;
ALTER TABLE transactions.delivery_events ADD COLUMN reason varchar(40);
ALTER TABLE transactions.deliveries ADD COLUMN courier_id uuid REFERENCES transactions.delivery_couriers(user_id);
ALTER TABLE transactions.deliveries ADD COLUMN search_started_at timestamptz;
ALTER TABLE transactions.deliveries ADD CONSTRAINT delivery_courier_not_sender CHECK (courier_id <> user_id);
CREATE UNIQUE INDEX deliveries_active_courier ON transactions.deliveries(courier_id)
    WHERE status IN ('COURIER_ASSIGNED','COURIER_ARRIVING','COURIER_ARRIVED','PICKED_UP','IN_TRANSIT',
                     'DELIVERED','DELIVERY_FAILED','RETURN_REQUESTED','RETURNING');

CREATE TABLE transactions.delivery_offers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id uuid NOT NULL REFERENCES transactions.deliveries(id),
    courier_id uuid NOT NULL REFERENCES transactions.delivery_couriers(user_id),
    state varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'ACCEPTED', 'REJECTED', 'EXPIRED')),
    expires_at timestamptz NOT NULL,
    UNIQUE (delivery_id, courier_id)
);
CREATE UNIQUE INDEX delivery_offers_pending_delivery ON transactions.delivery_offers(delivery_id) WHERE state = 'PENDING';
CREATE INDEX delivery_offers_courier_idx ON transactions.delivery_offers(courier_id, expires_at);

CREATE TABLE transactions.delivery_handoff_codes (
    delivery_id uuid PRIMARY KEY REFERENCES transactions.deliveries(id),
    token_hash bytea NOT NULL,
    expires_at timestamptz NOT NULL,
    failed_attempts smallint NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
    used_at timestamptz
);
