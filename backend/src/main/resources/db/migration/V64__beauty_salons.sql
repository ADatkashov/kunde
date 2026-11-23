-- Beauty & Care salons on top of the Booking engine: a salon is a booking venue (internal category BARBER) with a profile.
-- Offers, masters, schedules and double-booking protection stay in the Booking engine; this migration only adds the
-- discovery data (categories, location, gallery), service details, masters' specialty, reviews, favorites and promotions.
CREATE TABLE marketplace.beauty_salon_profiles (
    venue_id uuid PRIMARY KEY REFERENCES marketplace.booking_venues(id),
    category_codes text[] NOT NULL DEFAULT '{}',
    latitude numeric(9, 6) CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9, 6) CHECK (longitude BETWEEN -180 AND 180),
    verified boolean NOT NULL DEFAULT false,
    gallery_urls text[] NOT NULL DEFAULT '{}',
    phone varchar(32),
    cancellation_policy varchar(300) NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((latitude IS NULL) = (longitude IS NULL))
);
CREATE INDEX beauty_salon_profiles_categories_idx ON marketplace.beauty_salon_profiles USING gin (category_codes);

CREATE TABLE marketplace.beauty_service_profiles (
    service_id uuid PRIMARY KEY REFERENCES marketplace.booking_services(id),
    category_code varchar(32) COLLATE "C" REFERENCES marketplace.beauty_categories(code),
    tags text[] NOT NULL DEFAULT '{}',
    includes text[] NOT NULL DEFAULT '{}',
    preparation varchar(300) NOT NULL DEFAULT '',
    -- The price is "from" the shown amount; the final price is confirmed by the customer before booking.
    price_from boolean NOT NULL DEFAULT false,
    gallery_urls text[] NOT NULL DEFAULT '{}'
);

ALTER TABLE marketplace.booking_masters
    ADD COLUMN specialty varchar(120) NOT NULL DEFAULT '',
    ADD COLUMN experience_years smallint CHECK (experience_years IS NULL OR experience_years BETWEEN 0 AND 60);

-- A real review needs a completed booking of its author; synthetic DEV reviews carry neither.
CREATE TABLE marketplace.beauty_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    master_id uuid REFERENCES marketplace.booking_masters(id),
    service_id uuid REFERENCES marketplace.booking_services(id),
    booking_id uuid UNIQUE REFERENCES transactions.bookings(id),
    user_id uuid REFERENCES identity.users(id),
    author_name varchar(60) NOT NULL DEFAULT '',
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment varchar(1000) NOT NULL DEFAULT '',
    synthetic boolean NOT NULL DEFAULT false,
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'PUBLISHED' CHECK (status IN ('PUBLISHED', 'HIDDEN')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (synthetic OR (user_id IS NOT NULL AND booking_id IS NOT NULL))
);
CREATE INDEX beauty_reviews_venue_idx ON marketplace.beauty_reviews (venue_id, created_at DESC) WHERE status = 'PUBLISHED';

CREATE TABLE marketplace.beauty_favorites (
    user_id uuid NOT NULL REFERENCES identity.users(id),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, venue_id)
);

-- Percent discount shown on the Beauty banner and used for the «Акции» filter; venue_id NULL = platform-wide.
CREATE TABLE marketplace.beauty_promotions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid REFERENCES marketplace.booking_venues(id),
    title varchar(120) NOT NULL CHECK (length(btrim(title)) > 0),
    percent smallint NOT NULL CHECK (percent BETWEEN 1 AND 90),
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz NOT NULL,
    active boolean NOT NULL DEFAULT true,
    synthetic boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (ends_at > starts_at)
);
CREATE INDEX beauty_promotions_active_idx ON marketplace.beauty_promotions (venue_id) WHERE active;
