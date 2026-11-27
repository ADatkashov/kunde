-- Food: restaurant coordinates and a weekly opening schedule (Asia/Almaty local time).
-- Coordinates are optional (no distance is invented for restaurants without them). A restaurant WITHOUT schedule rows
-- keeps the previous behaviour (only the manual switch and moderation decide); WITH rows it is open only inside a slot.
ALTER TABLE marketplace.food_restaurants
    ADD COLUMN latitude numeric(9, 6) CHECK (latitude BETWEEN -90 AND 90),
    ADD COLUMN longitude numeric(9, 6) CHECK (longitude BETWEEN -180 AND 180),
    ADD CONSTRAINT food_restaurants_location_pair CHECK ((latitude IS NULL) = (longitude IS NULL));

-- day_of_week is ISO (1 = Monday .. 7 = Sunday). closes_at <= opens_at is an overnight slot that ends the next
-- morning (18:00-02:00); 24:00 closes at midnight (a full day is 00:00-24:00).
CREATE TABLE marketplace.food_restaurant_hours (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    day_of_week smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    opens_at time NOT NULL CHECK (opens_at < time '24:00'),
    closes_at time NOT NULL,
    CONSTRAINT food_restaurant_hours_not_empty CHECK (closes_at <> opens_at),
    CONSTRAINT food_restaurant_hours_slot UNIQUE (restaurant_id, day_of_week, opens_at)
);
CREATE INDEX food_restaurant_hours_restaurant_idx ON marketplace.food_restaurant_hours (restaurant_id, day_of_week);

-- True when the restaurant has no schedule, or `at` falls into one of its slots (local Asia/Almaty time; the
-- previous day's overnight slot counts until its closing time). Does NOT look at the manual switch or moderation.
CREATE FUNCTION marketplace.food_in_hours_at(rid uuid, at timestamptz) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (SELECT 1 FROM marketplace.food_restaurant_hours h WHERE h.restaurant_id = rid)
        OR EXISTS (
            SELECT 1
            FROM marketplace.food_restaurant_hours h,
                 LATERAL (SELECT at AT TIME ZONE 'Asia/Almaty' AS l) t
            WHERE h.restaurant_id = rid
              AND (
                  (h.day_of_week = extract(isodow FROM t.l)::int
                   AND t.l::time >= h.opens_at
                   AND (h.closes_at > h.opens_at AND t.l::time < h.closes_at OR h.closes_at <= h.opens_at))
                  OR
                  (h.closes_at <= h.opens_at
                   AND h.day_of_week = (extract(isodow FROM t.l)::int + 5) % 7 + 1
                   AND t.l::time < h.closes_at)
              )
        )
$$;

-- Effective "open now" used by every Food read and by checkout: manual switch AND not blocked AND inside the schedule.
CREATE FUNCTION marketplace.food_restaurant_open(r marketplace.food_restaurants) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT r.is_open AND r.moderation_status = 'ACTIVE' AND marketplace.food_in_hours_at(r.id, now())
$$;

-- Great-circle (straight-line) distance in metres; NULL when any coordinate is unknown. Road routing belongs to KUNDE Maps.
CREATE FUNCTION marketplace.food_distance_m(lat1 numeric, lon1 numeric, lat2 double precision, lon2 double precision)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN NULL
        ELSE round(2 * 6371000 * asin(least(1.0, sqrt(
            power(sin(radians(lat2 - lat1::float8) / 2), 2)
            + cos(radians(lat1::float8)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1::float8) / 2), 2)))))::int
    END
$$;
