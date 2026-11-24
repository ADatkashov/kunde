CREATE TABLE transactions.delivery_quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    parcel_type varchar(24) NOT NULL CHECK (parcel_type IN
        ('DOCUMENTS', 'SMALL_PARCEL', 'MEDIUM_PARCEL', 'PERSONAL_ITEMS', 'OTHER_ALLOWED_GOODS')),
    weight_grams integer NOT NULL CHECK (weight_grams BETWEEN 1 AND 50000),
    length_cm integer NOT NULL CHECK (length_cm BETWEEN 1 AND 200),
    width_cm integer NOT NULL CHECK (width_cm BETWEEN 1 AND 200),
    height_cm integer NOT NULL CHECK (height_cm BETWEEN 1 AND 200),
    pickup_latitude numeric(9,6) NOT NULL CHECK (pickup_latitude BETWEEN -90 AND 90),
    pickup_longitude numeric(9,6) NOT NULL CHECK (pickup_longitude BETWEEN -180 AND 180),
    destination_latitude numeric(9,6) NOT NULL CHECK (destination_latitude BETWEEN -90 AND 90),
    destination_longitude numeric(9,6) NOT NULL CHECK (destination_longitude BETWEEN -180 AND 180),
    distance_meters integer NOT NULL CHECK (distance_meters > 0),
    duration_seconds integer NOT NULL CHECK (duration_seconds > 0),
    synthetic_route boolean NOT NULL,
    tariff_version varchar(64) NOT NULL,
    amount_kzt numeric(14,2) NOT NULL CHECK (amount_kzt >= 0),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
    UNIQUE (user_id, id)
);

CREATE TABLE transactions.deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    quote_id uuid NOT NULL UNIQUE,
    request_key varchar(64) NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{16,64}$'),
    pickup_address varchar(240) NOT NULL,
    destination_address varchar(240) NOT NULL,
    recipient_name varchar(120) NOT NULL,
    recipient_phone varchar(16) NOT NULL,
    description varchar(300) NOT NULL,
    courier_note varchar(300),
    status varchar(32) NOT NULL CHECK (status IN ('CREATED', 'CANCELLED_BY_CUSTOMER')),
    created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    FOREIGN KEY (user_id, quote_id) REFERENCES transactions.delivery_quotes(user_id, id),
    UNIQUE (user_id, request_key)
);
CREATE INDEX deliveries_history_idx ON transactions.deliveries (user_id, created_at DESC, id DESC);

CREATE TABLE transactions.delivery_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    delivery_id uuid NOT NULL REFERENCES transactions.deliveries(id),
    actor_id uuid NOT NULL REFERENCES identity.users(id),
    status varchar(32) NOT NULL CHECK (status IN ('CREATED', 'CANCELLED_BY_CUSTOMER')),
    occurred_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    UNIQUE (delivery_id, status)
);

CREATE FUNCTION transactions.reject_delivery_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Delivery events are immutable';
END;
$$;
CREATE TRIGGER delivery_events_immutable BEFORE UPDATE OR DELETE ON transactions.delivery_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_delivery_event_mutation();
