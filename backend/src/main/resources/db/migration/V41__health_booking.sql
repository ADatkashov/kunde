ALTER TABLE marketplace.booking_venues DROP CONSTRAINT booking_venues_category_check;
ALTER TABLE marketplace.booking_venues ADD CONSTRAINT booking_venues_category_check
    CHECK (category IN ('BARBER', 'CLEANING', 'AUTO', 'HEALTH'));

ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_category_check;
ALTER TABLE transactions.bookings ADD CONSTRAINT bookings_category_check
    CHECK (category IN ('BARBER', 'CLEANING', 'AUTO', 'HEALTH'));
ALTER TABLE transactions.bookings ADD CONSTRAINT health_booking_no_free_text
    CHECK (category <> 'HEALTH' OR (comment IS NULL AND address_text IS NULL AND area_sqm IS NULL));

ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH'));
ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH'));

CREATE TABLE marketplace.health_categories (
    code varchar(24) PRIMARY KEY,
    medical boolean NOT NULL,
    name_ru varchar(80) NOT NULL,
    name_kk varchar(80) NOT NULL,
    name_en varchar(80) NOT NULL
);
INSERT INTO marketplace.health_categories VALUES
    ('DOCTORS', true, 'Врачи', 'Дәрігерлер', 'Doctors'),
    ('CLINICS', true, 'Клиники', 'Клиникалар', 'Clinics'),
    ('DENTISTRY', true, 'Стоматология', 'Стоматология', 'Dentistry'),
    ('DIAGNOSTICS', true, 'Диагностика', 'Диагностика', 'Diagnostics'),
    ('LABS', true, 'Анализы', 'Талдаулар', 'Lab tests'),
    ('FITNESS', false, 'Фитнес', 'Фитнес', 'Fitness'),
    ('SPA', false, 'SPA и массаж', 'SPA және массаж', 'Spa and massage'),
    ('WELLNESS', false, 'Другие услуги', 'Басқа қызметтер', 'Other services');

ALTER TABLE marketplace.booking_services
    ADD COLUMN health_category varchar(24) REFERENCES marketplace.health_categories(code);
CREATE INDEX booking_services_health_category_idx
    ON marketplace.booking_services (health_category, venue_id) WHERE available AND health_category IS NOT NULL;

ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS'));

CREATE TABLE marketplace.health_moderation_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venue_id uuid NOT NULL REFERENCES marketplace.booking_venues(id),
    admin_user_id uuid NOT NULL REFERENCES identity.users(id),
    published boolean NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER health_moderation_events_immutable BEFORE UPDATE OR DELETE ON marketplace.health_moderation_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

ALTER TABLE marketplace.booking_venues ADD COLUMN health_published boolean NOT NULL DEFAULT true;

ALTER TABLE transactions.bookings ADD COLUMN health_initial_starts_at timestamptz;
ALTER TABLE transactions.bookings ADD CONSTRAINT health_initial_start_required
    CHECK ((category = 'HEALTH') = (health_initial_starts_at IS NOT NULL));
