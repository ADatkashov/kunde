-- Rides uses the canonical customer account and the existing transactions schema.
CREATE TABLE transactions.ride_fare_quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    ride_class varchar(12) NOT NULL CHECK (ride_class IN ('ECONOMY', 'COMFORT', 'BUSINESS')),
    tariff_version varchar(64) NOT NULL CHECK (length(tariff_version) > 0),
    estimate_kzt numeric(14, 2) NOT NULL CHECK (estimate_kzt >= 0),
    distance_meters integer NOT NULL CHECK (distance_meters > 0),
    duration_seconds integer NOT NULL CHECK (duration_seconds > 0),
    pickup_latitude numeric(9, 6) NOT NULL CHECK (pickup_latitude BETWEEN -90 AND 90),
    pickup_longitude numeric(9, 6) NOT NULL CHECK (pickup_longitude BETWEEN -180 AND 180),
    destination_latitude numeric(9, 6) NOT NULL CHECK (destination_latitude BETWEEN -90 AND 90),
    destination_longitude numeric(9, 6) NOT NULL CHECK (destination_longitude BETWEEN -180 AND 180),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
    UNIQUE (user_id, id)
);

CREATE TABLE transactions.rides (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    quote_id uuid NOT NULL UNIQUE,
    request_key varchar(64) NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{16,64}$'),
    status varchar(24) NOT NULL CHECK (status IN ('REQUESTED', 'CANCELLED_BY_CUSTOMER')),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, quote_id) REFERENCES transactions.ride_fare_quotes(user_id, id),
    UNIQUE (user_id, request_key)
);
CREATE INDEX rides_user_history_idx ON transactions.rides (user_id, created_at DESC, id DESC);
CREATE UNIQUE INDEX rides_one_pending_per_customer ON transactions.rides (user_id) WHERE status = 'REQUESTED';

CREATE TABLE transactions.ride_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ride_id uuid NOT NULL REFERENCES transactions.rides(id),
    status varchar(24) NOT NULL CHECK (status IN ('REQUESTED', 'CANCELLED_BY_CUSTOMER')),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (ride_id, status)
);

CREATE FUNCTION transactions.reject_ride_history_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Ride events and quoted fares are immutable';
END;
$$;
CREATE TRIGGER ride_events_immutable BEFORE UPDATE OR DELETE ON transactions.ride_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_ride_history_mutation();
CREATE TRIGGER ride_fare_quotes_immutable BEFORE UPDATE ON transactions.ride_fare_quotes
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_ride_history_mutation();
