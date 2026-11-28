-- Booking remains the source of truth for the current assignment.
ALTER TABLE transactions.bookings
    ALTER COLUMN master_id DROP NOT NULL,
    ADD COLUMN home_initial_master_id uuid,
    ADD COLUMN home_latitude double precision,
    ADD COLUMN home_longitude double precision,
    ADD CONSTRAINT bookings_unassigned_home_service CHECK (
        master_id IS NOT NULL OR (category = 'CLEANING' AND status IN ('PENDING', 'CONFIRMED', 'CANCELLED'))
    );

-- H8 could reassign an order before the original master was stored on Booking.
UPDATE transactions.bookings b
SET home_initial_master_id = (
    SELECT e.from_master_id FROM marketplace.home_service_admin_events e
    WHERE e.booking_id = b.id AND e.action = 'REASSIGN' ORDER BY e.id LIMIT 1
)
WHERE b.category = 'CLEANING' AND EXISTS (
    SELECT 1 FROM marketplace.home_service_admin_events e WHERE e.booking_id = b.id AND e.action = 'REASSIGN'
);

ALTER TABLE transactions.booking_events DROP CONSTRAINT booking_events_actor_type_check;
ALTER TABLE transactions.booking_events ADD CONSTRAINT booking_events_actor_type_check
    CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'SYSTEM', 'ADMIN', 'EXECUTOR'));
ALTER TABLE transactions.booking_events
    ADD COLUMN assignment_version bigint,
    ADD COLUMN from_master_id uuid,
    ADD COLUMN to_master_id uuid,
    ADD CONSTRAINT booking_events_assignment_version_unique UNIQUE (booking_id, assignment_version);
