-- Canonical identity and explicitly granted ride moderation.
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check
    CHECK (permission IN ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION'));

CREATE TABLE transactions.ride_drivers (
    user_id uuid PRIMARY KEY REFERENCES identity.users(id),
    display_name varchar(80) NOT NULL CHECK (length(btrim(display_name)) > 0),
    status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'BLOCKED')),
    online boolean NOT NULL DEFAULT false,
    latitude numeric(9, 6) CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9, 6) CHECK (longitude BETWEEN -180 AND 180),
    observed_at timestamptz,
    CHECK (NOT online OR status = 'APPROVED'),
    CHECK (num_nonnulls(latitude, longitude, observed_at) IN (0, 3)),
    CHECK (online OR observed_at IS NULL)
);

CREATE TABLE transactions.ride_vehicles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id uuid NOT NULL REFERENCES transactions.ride_drivers(user_id),
    description varchar(100) NOT NULL CHECK (length(btrim(description)) > 0),
    plate varchar(16) NOT NULL UNIQUE,
    ride_class varchar(12) NOT NULL CHECK (ride_class IN ('ECONOMY', 'COMFORT', 'BUSINESS')),
    status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'BLOCKED')),
    UNIQUE (driver_id)
);

CREATE TABLE transactions.ride_driver_review_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    driver_id uuid NOT NULL REFERENCES transactions.ride_drivers(user_id),
    vehicle_id uuid REFERENCES transactions.ride_vehicles(id),
    reviewer_id uuid NOT NULL REFERENCES identity.users(id),
    status varchar(12) NOT NULL CHECK (status IN ('APPROVED', 'BLOCKED')),
    occurred_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    CHECK (reviewer_id <> driver_id)
);
CREATE TRIGGER ride_driver_review_events_immutable BEFORE UPDATE OR DELETE ON transactions.ride_driver_review_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_ride_history_mutation();

ALTER TABLE transactions.rides DROP CONSTRAINT rides_status_check;
ALTER TABLE transactions.ride_events DROP CONSTRAINT ride_events_status_check;
ALTER TABLE transactions.rides ADD CONSTRAINT rides_status_check CHECK (status IN
    ('REQUESTED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED',
     'IN_PROGRESS', 'COMPLETED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_DRIVER', 'CANCELLED_BY_SYSTEM',
     'NO_DRIVER_AVAILABLE', 'FAILED'));
ALTER TABLE transactions.ride_events ADD CONSTRAINT ride_events_status_check CHECK (status IN
    ('REQUESTED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED',
     'IN_PROGRESS', 'COMPLETED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_DRIVER', 'CANCELLED_BY_SYSTEM',
     'NO_DRIVER_AVAILABLE', 'FAILED'));
ALTER TABLE transactions.rides ADD COLUMN driver_id uuid REFERENCES transactions.ride_drivers(user_id);
ALTER TABLE transactions.rides ADD COLUMN search_started_at timestamptz;
DROP INDEX transactions.rides_one_pending_per_customer;
CREATE UNIQUE INDEX rides_active_customer ON transactions.rides (user_id)
    WHERE status IN ('REQUESTED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS');
CREATE UNIQUE INDEX rides_active_driver ON transactions.rides (driver_id)
    WHERE status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS');

CREATE TABLE transactions.ride_offers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id uuid NOT NULL REFERENCES transactions.rides(id),
    driver_id uuid NOT NULL REFERENCES transactions.ride_drivers(user_id),
    state varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'ACCEPTED', 'REJECTED', 'EXPIRED')),
    expires_at timestamptz NOT NULL,
    UNIQUE (ride_id, driver_id)
);
CREATE UNIQUE INDEX ride_offers_pending_ride ON transactions.ride_offers (ride_id) WHERE state = 'PENDING';
CREATE INDEX ride_offers_driver ON transactions.ride_offers (driver_id, expires_at);
