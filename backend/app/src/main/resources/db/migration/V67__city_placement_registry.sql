-- Database sharding readiness, phase 1 (docs/architecture/database-sharding-readiness.md). EXPAND ONLY:
-- nothing here changes behaviour of a running API, nothing is backfilled and no city is invented.
--
--  * serviceability.cities  - global registry of cities and the logical shard that holds their operational data.
--                             Empty on purpose: which cities exist and are enabled is an owner decision (see V3).
--  * city_id (nullable)     - placement key on the aggregate roots that are anchored to a place. Children (orders, bookings,
--                             tickets, enrolments...) inherit placement from their root and get no copy of the column.
--  * immutability trigger   - once a root has a city it can never move through an ordinary UPDATE. Re-homing is a
--                             controlled data migration, not an edit.
-- Existing rows keep city_id NULL ("unplaced") until a reviewed mapping exists; NULL is never silently replaced.
CREATE TABLE serviceability.cities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) COLLATE "C" NOT NULL UNIQUE CHECK (code ~ '^[a-z0-9][a-z0-9_-]*$'),
    country_code char(2) NOT NULL DEFAULT 'KZ' CHECK (country_code ~ '^[A-Z]{2}$'),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    timezone varchar(40) NOT NULL DEFAULT 'Asia/Almaty',
    -- Logical shard id. Every city lives on 'default' (the single existing PostgreSQL) until a shard is actually provisioned.
    shard_id varchar(32) COLLATE "C" NOT NULL DEFAULT 'default' CHECK (shard_id ~ '^[a-z0-9][a-z0-9_-]*$'),
    enabled boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cities_shard_idx ON serviceability.cities (shard_id) WHERE enabled;

CREATE FUNCTION serviceability.forbid_city_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.city_id IS NOT NULL AND NEW.city_id IS DISTINCT FROM OLD.city_id THEN
        RAISE EXCEPTION 'city_id of %.% is immutable once assigned (placement key)', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END
$$;

-- ADD COLUMN without a default is a catalog-only change in PostgreSQL 16 (no table rewrite, no long lock).
ALTER TABLE marketplace.food_restaurants  ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
ALTER TABLE marketplace.booking_venues    ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
ALTER TABLE marketplace.leisure_venues    ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
ALTER TABLE marketplace.education_courses ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
ALTER TABLE transactions.rides            ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
ALTER TABLE transactions.deliveries       ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
ALTER TABLE transactions.auto_jobs        ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);

CREATE TRIGGER food_restaurants_city_immutable  BEFORE UPDATE OF city_id ON marketplace.food_restaurants
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();
CREATE TRIGGER booking_venues_city_immutable    BEFORE UPDATE OF city_id ON marketplace.booking_venues
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();
CREATE TRIGGER leisure_venues_city_immutable    BEFORE UPDATE OF city_id ON marketplace.leisure_venues
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();
CREATE TRIGGER education_courses_city_immutable BEFORE UPDATE OF city_id ON marketplace.education_courses
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();
CREATE TRIGGER rides_city_immutable             BEFORE UPDATE OF city_id ON transactions.rides
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();
CREATE TRIGGER deliveries_city_immutable        BEFORE UPDATE OF city_id ON transactions.deliveries
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();
CREATE TRIGGER auto_jobs_city_immutable         BEFORE UPDATE OF city_id ON transactions.auto_jobs
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();

-- Indexes only where the table is a small catalogue; partial, so they stay empty until placement exists.
-- rides/deliveries/auto_jobs are intentionally NOT indexed here: build the index CONCURRENTLY together with the
-- backfill (contract phase), not inside this transactional migration.
CREATE INDEX food_restaurants_city_idx  ON marketplace.food_restaurants (city_id)  WHERE city_id IS NOT NULL;
CREATE INDEX booking_venues_city_idx    ON marketplace.booking_venues (city_id)    WHERE city_id IS NOT NULL;
CREATE INDEX leisure_venues_city_idx    ON marketplace.leisure_venues (city_id)    WHERE city_id IS NOT NULL;
CREATE INDEX education_courses_city_idx ON marketplace.education_courses (city_id) WHERE city_id IS NOT NULL;
