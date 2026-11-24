-- Booking MVP (DEV pilot): barbershop appointments. Venue -> service -> master -> free slot -> confirmation.
-- Catalog/schedule tables live in marketplace, bookings in transactions. No rows are seeded here: synthetic venues come
-- from the guarded DEV seeder (app.booking.seed-demo). Prices are integer KZT minor units; payment is on site (no provider).
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE marketplace.booking_venues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug varchar(64) COLLATE "C" NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]*$'),
    category varchar(16) COLLATE "C" NOT NULL DEFAULT 'BARBER' CHECK (category IN ('BARBER', 'CLEANING')),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    description varchar(500) NOT NULL DEFAULT '',
    address_text varchar(300) NOT NULL CHECK (length(btrim(address_text)) > 0),
    emoji varchar(16) NOT NULL DEFAULT '💈',
    tone varchar(16) NOT NULL DEFAULT 'blue',
    image_url varchar(500) CHECK (image_url IS NULL OR image_url ~ '^https://'),
    timezone varchar(40) NOT NULL DEFAULT 'Asia/Almaty',
    is_open boolean NOT NULL DEFAULT true,
    is_synthetic boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE marketplace.booking_services (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    description varchar(300) NOT NULL DEFAULT '',
    duration_minutes integer NOT NULL CHECK (duration_minutes BETWEEN 15 AND 240 AND duration_minutes % 15 = 0),
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    available boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX booking_services_venue_idx ON marketplace.booking_services (venue_id, sort_order);

CREATE TABLE marketplace.booking_masters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    bio varchar(300) NOT NULL DEFAULT '',
    emoji varchar(16) NOT NULL DEFAULT '💇',
    tone varchar(16) NOT NULL DEFAULT 'amber',
    active boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX booking_masters_venue_idx ON marketplace.booking_masters (venue_id, sort_order);

CREATE TABLE marketplace.booking_master_services (
    master_id uuid NOT NULL REFERENCES marketplace.booking_masters(id),
    service_id uuid NOT NULL REFERENCES marketplace.booking_services(id),
    PRIMARY KEY (master_id, service_id)
);

-- One working interval per ISO weekday (1 = Monday); a missing weekday is a day off. Optional break inside the day.
CREATE TABLE marketplace.booking_working_hours (
    master_id uuid NOT NULL REFERENCES marketplace.booking_masters(id),
    weekday smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    start_time time NOT NULL,
    end_time time NOT NULL,
    break_start time,
    break_end time,
    PRIMARY KEY (master_id, weekday),
    CHECK (end_time > start_time),
    CHECK ((break_start IS NULL) = (break_end IS NULL)),
    CHECK (break_start IS NULL OR (break_end > break_start AND break_start >= start_time AND break_end <= end_time))
);

CREATE TABLE transactions.bookings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    service_id uuid NOT NULL REFERENCES marketplace.booking_services(id),
    master_id uuid NOT NULL REFERENCES marketplace.booking_masters(id),
    venue_name varchar(120) NOT NULL,
    venue_address varchar(300) NOT NULL,
    service_name varchar(120) NOT NULL,
    master_name varchar(120) NOT NULL,
    duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    status varchar(16) COLLATE "C" NOT NULL DEFAULT 'CONFIRMED' CHECK (status IN ('CONFIRMED', 'CANCELLED', 'COMPLETED')),
    -- DEV mock: the booking is confirmed instantly by the platform; no real master/venue acknowledgement exists yet.
    confirmation varchar(16) COLLATE "C" NOT NULL DEFAULT 'DEV_MOCK' CHECK (confirmation IN ('DEV_MOCK')),
    comment varchar(300),
    idempotency_key varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    cancelled_at timestamptz,
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT bookings_idempotency UNIQUE (user_id, idempotency_key),
    CONSTRAINT bookings_time_order CHECK (ends_at > starts_at),
    CONSTRAINT bookings_cancel_ts CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL)),
    -- No double booking: one master cannot have two confirmed bookings with overlapping time.
    CONSTRAINT bookings_master_no_overlap EXCLUDE USING gist (
        master_id WITH =, tstzrange(starts_at, ends_at) WITH &&) WHERE (status IN ('CONFIRMED', 'COMPLETED'))
);
CREATE INDEX bookings_user_idx ON transactions.bookings (user_id, starts_at DESC, id);
CREATE INDEX bookings_master_idx ON transactions.bookings (master_id, starts_at);
