-- Visit progress of a Home Services booking, owned by Home Services: the master is on the way, then on site. The booking itself
-- keeps the Booking Engine statuses (CONFIRMED -> IN_PROGRESS -> COMPLETED); the stage only refines CONFIRMED for the customer.
CREATE TABLE marketplace.home_service_visits (
    booking_id uuid PRIMARY KEY REFERENCES transactions.bookings(id),
    stage varchar(12) COLLATE "C" NOT NULL CHECK (stage IN ('EN_ROUTE', 'ARRIVED')),
    eta_minutes integer CHECK (eta_minutes IS NULL OR eta_minutes BETWEEN 0 AND 600),
    en_route_at timestamptz NOT NULL DEFAULT now(),
    arrived_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT home_service_visits_arrived_ts CHECK ((stage = 'ARRIVED') = (arrived_at IS NOT NULL))
);
