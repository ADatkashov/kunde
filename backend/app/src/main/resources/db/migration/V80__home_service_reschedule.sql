ALTER TABLE transactions.bookings
    ADD COLUMN home_initial_starts_at timestamptz,
    ADD COLUMN home_proposed_starts_at timestamptz,
    ADD COLUMN home_reschedule_reason varchar(200),
    ADD CONSTRAINT bookings_home_reschedule_proposal CHECK (
        (home_proposed_starts_at IS NULL AND home_reschedule_reason IS NULL)
        OR (category = 'CLEANING' AND home_proposed_starts_at IS NOT NULL AND home_reschedule_reason IS NOT NULL)
    );
