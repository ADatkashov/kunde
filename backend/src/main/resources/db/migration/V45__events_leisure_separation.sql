-- KUNDE Events & Tickets / Leisure & Entertainment: separation of two products on ONE canonical engine (no new inventory tables).
-- Ticketed dated events (cinema, concerts, theatre, sport, festivals, shows) belong to EVENTS; bookable activities belong to LEISURE.
ALTER TABLE marketplace.leisure_categories
    ADD COLUMN product varchar(8) COLLATE "C" NOT NULL DEFAULT 'LEISURE' CHECK (product IN ('EVENTS', 'LEISURE'));
UPDATE marketplace.leisure_categories SET product = 'EVENTS' WHERE code IN ('CINEMA', 'CONCERT', 'THEATER', 'EXHIBITION');
CREATE INDEX leisure_categories_product_idx ON marketplace.leisure_categories (product, sort_order);

INSERT INTO marketplace.leisure_categories (code, name_ru, name_kk, name_en, default_booking_type, family_friendly, needs_executor, sort_order, product) VALUES
    ('SPORT', 'Спорт', 'Спорт', 'Sports matches', 'SEAT_MAP', true, false, 17, 'EVENTS'),
    ('FESTIVAL', 'Фестивали', 'Фестивальдер', 'Festivals', 'GENERAL_ADMISSION', true, false, 18, 'EVENTS'),
    ('SHOW', 'Шоу', 'Шоу', 'Shows', 'SEAT_MAP', true, false, 19, 'EVENTS'),
    ('STANDUP', 'Стендап', 'Стендап', 'Stand-up', 'SEAT_MAP', false, false, 20, 'EVENTS'),
    ('KIDS_SHOW', 'Детские представления', 'Балалар қойылымдары', 'Kids shows', 'SEAT_MAP', true, false, 21, 'EVENTS'),
    ('KARTING', 'Картинг', 'Картинг', 'Karting', 'TIME_SLOT', false, false, 22, 'LEISURE'),
    ('LASER_TAG', 'Лазертаг', 'Лазертаг', 'Laser tag', 'CAPACITY', true, false, 23, 'LEISURE'),
    ('CLIMBING', 'Скалодромы', 'Скалодромдар', 'Climbing gyms', 'CAPACITY', true, false, 24, 'LEISURE'),
    ('PAINTBALL', 'Пейнтбол', 'Пейнтбол', 'Paintball', 'CAPACITY', false, false, 25, 'LEISURE'),
    ('BOARD_GAMES', 'Настольные игры', 'Үстел ойындары', 'Board games', 'TIME_SLOT', true, false, 26, 'LEISURE');

ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'EVENTS'));
ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'EVENTS'));
