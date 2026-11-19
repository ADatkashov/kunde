CREATE TABLE transactions.delivery_locations (
    delivery_id uuid PRIMARY KEY REFERENCES transactions.deliveries(id),
    latitude numeric(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    observed_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

CREATE INDEX delivery_locations_expiry_idx ON transactions.delivery_locations(observed_at);
CREATE INDEX deliveries_waiting_dispatch_idx ON transactions.deliveries(search_started_at, id)
    WHERE status = 'SEARCHING_COURIER';

CREATE FUNCTION transactions.clear_inactive_delivery_location() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status NOT IN ('COURIER_ASSIGNED','COURIER_ARRIVING','COURIER_ARRIVED',
                          'PICKED_UP','IN_TRANSIT','RETURNING') THEN
        DELETE FROM transactions.delivery_locations WHERE delivery_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER delivery_location_end AFTER UPDATE OF status ON transactions.deliveries
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION transactions.clear_inactive_delivery_location();
