-- KUNDE Auto 1.0 (DEV/TEST): automotive services reuse the Booking engine. A venue of category AUTO is a service station /
-- car wash, a "master" is a service post (bay) or technician, slots and double-booking protection are unchanged.
-- Added here: vehicles, auto categories, price kinds, venue buffer, time off, server-side quotes, extra lifecycle states.
-- No organisations, prices or vehicles are seeded; synthetic data comes only from the guarded DEV seeder.

ALTER TABLE marketplace.booking_venues DROP CONSTRAINT booking_venues_category_check;
ALTER TABLE marketplace.booking_venues
    ADD CONSTRAINT booking_venues_category_check CHECK (category IN ('BARBER', 'CLEANING', 'AUTO')),
    ADD COLUMN buffer_minutes integer NOT NULL DEFAULT 0 CHECK (buffer_minutes BETWEEN 0 AND 120);

CREATE TABLE marketplace.auto_service_categories (
    code varchar(24) COLLATE "C" PRIMARY KEY CHECK (code ~ '^[A-Z_]+$'),
    name_ru varchar(80) NOT NULL,
    name_kk varchar(80) NOT NULL,
    name_en varchar(80) NOT NULL,
    mobile boolean NOT NULL DEFAULT false,
    enabled boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0
);
INSERT INTO marketplace.auto_service_categories (code, name_ru, name_kk, name_en, mobile, sort_order) VALUES
    ('CAR_WASH', 'Автомойка', 'Көлік жуу', 'Car wash', false, 1),
    ('TIRE', 'Шиномонтаж', 'Шина орнату', 'Tire service', false, 2),
    ('OIL_CHANGE', 'Замена масла', 'Май ауыстыру', 'Oil change', false, 3),
    ('DIAGNOSTICS', 'Диагностика', 'Диагностика', 'Diagnostics', false, 4),
    ('MAINTENANCE', 'Техническое обслуживание', 'Техникалық қызмет көрсету', 'Maintenance', false, 5),
    ('REPAIR', 'Ремонт автомобиля', 'Көлікті жөндеу', 'Repair', false, 6),
    ('ROADSIDE', 'Выездная помощь', 'Жолдағы көмек', 'Roadside assistance', true, 7),
    ('OTHER', 'Другие услуги', 'Басқа қызметтер', 'Other services', false, 8);

-- FIXED: the price is final; FROM: "from" price, final cost is agreed after inspection; DIAGNOSTIC: the diagnostic price
-- is fixed and any follow-up work is agreed separately.
ALTER TABLE marketplace.booking_services
    ADD COLUMN auto_category varchar(24) COLLATE "C" REFERENCES marketplace.auto_service_categories(code),
    ADD COLUMN price_kind varchar(12) COLLATE "C" NOT NULL DEFAULT 'FIXED' CHECK (price_kind IN ('FIXED', 'FROM', 'DIAGNOSTIC')),
    ADD COLUMN conditions varchar(300) NOT NULL DEFAULT '';

-- Unavailable periods (a whole venue when master_id is null, otherwise one post): holidays, repairs, days off.
CREATE TABLE marketplace.booking_time_off (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    master_id uuid REFERENCES marketplace.booking_masters(id),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    reason varchar(200) NOT NULL DEFAULT '',
    created_by uuid REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (ends_at > starts_at)
);
CREATE INDEX booking_time_off_venue_idx ON marketplace.booking_time_off (venue_id, starts_at);

CREATE TABLE transactions.customer_vehicles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    make varchar(40) NOT NULL CHECK (length(btrim(make)) > 0),
    model varchar(40) NOT NULL CHECK (length(btrim(model)) > 0),
    production_year integer NOT NULL CHECK (production_year BETWEEN 1950 AND 2100),
    plate varchar(16),
    archived boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0
);
CREATE INDEX customer_vehicles_user_idx ON transactions.customer_vehicles (user_id) WHERE NOT archived;

-- A quote fixes the server-computed price for one vehicle/service/time for a short period. A booking can only be made from a
-- valid quote, so the client can never choose the price.
CREATE TABLE transactions.auto_quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    service_id uuid NOT NULL REFERENCES marketplace.booking_services(id),
    vehicle_id uuid NOT NULL REFERENCES transactions.customer_vehicles(id),
    master_id uuid NOT NULL REFERENCES marketplace.booking_masters(id),
    starts_at timestamptz NOT NULL,
    duration_minutes integer NOT NULL,
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    price_kind varchar(12) COLLATE "C" NOT NULL,
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_category_check;
ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_status_check;
ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_master_no_overlap;
ALTER TABLE transactions.bookings
    ADD CONSTRAINT bookings_category_check CHECK (category IN ('BARBER', 'CLEANING', 'AUTO')),
    ADD CONSTRAINT bookings_status_check CHECK (status IN
        ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'CANCELLED', 'COMPLETED', 'NO_SHOW')),
    ADD COLUMN vehicle_id uuid REFERENCES transactions.customer_vehicles(id),
    ADD COLUMN vehicle_label varchar(120),
    ADD COLUMN price_kind varchar(12) COLLATE "C" NOT NULL DEFAULT 'FIXED' CHECK (price_kind IN ('FIXED', 'FROM', 'DIAGNOSTIC')),
    ADD COLUMN final_price_minor bigint CHECK (final_price_minor IS NULL OR final_price_minor >= 0),
    ADD COLUMN price_approval varchar(10) COLLATE "C" CHECK (price_approval IN ('PENDING', 'APPROVED', 'DECLINED')),
    ADD COLUMN reschedule_count integer NOT NULL DEFAULT 0,
    ADD CONSTRAINT bookings_auto_vehicle CHECK ((category = 'AUTO') = (vehicle_id IS NOT NULL)),
    ADD CONSTRAINT bookings_master_no_overlap EXCLUDE USING gist (
        master_id WITH =, tstzrange(starts_at, ends_at) WITH &&)
        WHERE (status IN ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'COMPLETED'));

ALTER TABLE transactions.booking_events DROP CONSTRAINT booking_events_status_check;
ALTER TABLE transactions.booking_events ADD CONSTRAINT booking_events_status_check CHECK (status IN
    ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_PROGRESS', 'CANCELLED', 'COMPLETED', 'NO_SHOW', 'RESCHEDULED'));

ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS'));

-- Append-only record of administrator actions on Auto (category switches, venue blocks).
CREATE TABLE marketplace.auto_admin_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_user_id uuid NOT NULL REFERENCES identity.users(id),
    action varchar(40) NOT NULL,
    target varchar(80) NOT NULL,
    detail varchar(300),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER auto_admin_events_immutable BEFORE UPDATE OR DELETE ON marketplace.auto_admin_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
