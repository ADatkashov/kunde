-- KUNDE Auto: customer complaints (booking or on-site job) with administrator resolution, and reviews of completed bookings.
-- Complaints and reviews carry no contact data; administrators see the text the customer wrote and the booking/job reference only.

CREATE TABLE transactions.auto_complaints (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    booking_id uuid REFERENCES transactions.bookings(id),
    job_id uuid REFERENCES transactions.auto_jobs(id),
    kind varchar(16) COLLATE "C" NOT NULL CHECK (kind IN ('QUALITY', 'PRICE', 'BEHAVIOR', 'NO_SHOW', 'OTHER')),
    description varchar(500) NOT NULL CHECK (length(btrim(description)) >= 5),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED')),
    resolution varchar(300),
    resolved_by uuid REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CHECK (num_nonnulls(booking_id, job_id) = 1),
    CHECK ((status = 'RESOLVED') = (resolved_at IS NOT NULL AND resolved_by IS NOT NULL AND resolution IS NOT NULL))
);
-- One open complaint per customer and subject: a repeated tap cannot flood the queue.
CREATE UNIQUE INDEX auto_complaints_open_booking ON transactions.auto_complaints (user_id, booking_id) WHERE status = 'OPEN' AND booking_id IS NOT NULL;
CREATE UNIQUE INDEX auto_complaints_open_job ON transactions.auto_complaints (user_id, job_id) WHERE status = 'OPEN' AND job_id IS NOT NULL;
CREATE INDEX auto_complaints_status_idx ON transactions.auto_complaints (status, created_at DESC);

CREATE TABLE transactions.auto_reviews (
    booking_id uuid PRIMARY KEY REFERENCES transactions.bookings(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    text varchar(500) NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auto_reviews_venue_idx ON transactions.auto_reviews (venue_id, created_at DESC);
