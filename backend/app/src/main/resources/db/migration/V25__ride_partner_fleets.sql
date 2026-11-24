CREATE TABLE transactions.ride_fleets (
    partner_id uuid PRIMARY KEY REFERENCES marketplace.partners(id),
    status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'BLOCKED')),
    created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
ALTER TABLE transactions.ride_drivers ADD COLUMN fleet_partner_id uuid REFERENCES transactions.ride_fleets(partner_id);
ALTER TABLE transactions.rides ADD COLUMN fleet_partner_id uuid REFERENCES transactions.ride_fleets(partner_id);
CREATE INDEX rides_fleet_history ON transactions.rides (fleet_partner_id, created_at DESC) WHERE fleet_partner_id IS NOT NULL;
CREATE INDEX ride_drivers_fleet ON transactions.ride_drivers (fleet_partner_id) WHERE fleet_partner_id IS NOT NULL;

CREATE TABLE transactions.ride_fleet_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_id uuid NOT NULL REFERENCES transactions.ride_fleets(partner_id),
    actor_id uuid NOT NULL REFERENCES identity.users(id),
    driver_id uuid REFERENCES transactions.ride_drivers(user_id),
    action varchar(16) NOT NULL CHECK (action IN ('APPLIED', 'APPROVED', 'BLOCKED', 'ATTACHED', 'DETACHED')),
    occurred_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    CHECK ((action IN ('ATTACHED', 'DETACHED')) = (driver_id IS NOT NULL))
);
CREATE TRIGGER ride_fleet_events_immutable BEFORE UPDATE OR DELETE ON transactions.ride_fleet_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_ride_history_mutation();
