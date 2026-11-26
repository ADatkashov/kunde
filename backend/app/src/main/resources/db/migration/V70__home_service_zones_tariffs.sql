-- Home Services commercial layer. A venue serves circular zones (centre and radius, checked server-side against the address
-- coordinates; a venue without active zones serves the whole city). An offer may carry surcharges that the Booking Engine adds
-- to the list price through the HomeServices BookingCategory hook, so the public quote and the booking always agree.
CREATE TABLE marketplace.home_service_zones (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    name varchar(80) NOT NULL CHECK (length(btrim(name)) > 0),
    center_lat double precision NOT NULL CHECK (center_lat BETWEEN -90 AND 90),
    center_lng double precision NOT NULL CHECK (center_lng BETWEEN -180 AND 180),
    radius_m integer NOT NULL CHECK (radius_m BETWEEN 300 AND 100000),
    active boolean NOT NULL DEFAULT true,
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX home_service_zones_venue_idx ON marketplace.home_service_zones (venue_id) WHERE active;

CREATE TABLE marketplace.home_service_tariffs (
    offer_id uuid PRIMARY KEY REFERENCES marketplace.home_service_offers(id),
    call_out_fee_minor bigint NOT NULL DEFAULT 0 CHECK (call_out_fee_minor BETWEEN 0 AND 100000000),
    urgent_surcharge_percent integer NOT NULL DEFAULT 0 CHECK (urgent_surcharge_percent BETWEEN 0 AND 100),
    evening_surcharge_percent integer NOT NULL DEFAULT 0 CHECK (evening_surcharge_percent BETWEEN 0 AND 100),
    evening_from time NOT NULL DEFAULT '20:00',
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    updated_at timestamptz NOT NULL DEFAULT now()
);
