-- Minivan is a fourth ride class. It has no default tariff: the class stays unavailable
-- (RIDE_CLASS_UNAVAILABLE) until an owner-approved tariff is configured.
ALTER TABLE transactions.ride_fare_quotes DROP CONSTRAINT ride_fare_quotes_ride_class_check;
ALTER TABLE transactions.ride_fare_quotes ADD CONSTRAINT ride_fare_quotes_ride_class_check
    CHECK (ride_class IN ('ECONOMY', 'COMFORT', 'BUSINESS', 'MINIVAN'));
ALTER TABLE transactions.ride_vehicles DROP CONSTRAINT ride_vehicles_ride_class_check;
ALTER TABLE transactions.ride_vehicles ADD CONSTRAINT ride_vehicles_ride_class_check
    CHECK (ride_class IN ('ECONOMY', 'COMFORT', 'BUSINESS', 'MINIVAN'));

-- One rating per completed ride, written once by the customer. Ratings are immutable so
-- driver averages cannot be rewritten after the fact.
CREATE TABLE transactions.ride_ratings (
    ride_id uuid PRIMARY KEY REFERENCES transactions.rides(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    driver_id uuid NOT NULL REFERENCES transactions.ride_drivers(user_id),
    stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
    comment varchar(500) CHECK (comment IS NULL OR length(btrim(comment)) > 0),
    created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX ride_ratings_driver_idx ON transactions.ride_ratings (driver_id);
CREATE TRIGGER ride_ratings_immutable BEFORE UPDATE OR DELETE ON transactions.ride_ratings
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_ride_history_mutation();
