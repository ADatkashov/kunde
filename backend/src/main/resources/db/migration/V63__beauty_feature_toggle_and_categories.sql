-- Beauty & Care: runtime switch (off by default, see BeautySettings) and the category taxonomy shown on the Beauty home.
-- Bookable offers, prices and schedules stay in the Booking engine; categories only classify them.
ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'GROCERIES', 'EVENTS', 'HOME_SERVICES', 'BEAUTY'));

ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'GROCERIES', 'EVENTS', 'HOME_SERVICES', 'BEAUTY'));

CREATE TABLE marketplace.beauty_categories (
    code varchar(32) COLLATE "C" PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,31}$'),
    name_ru varchar(120) NOT NULL CHECK (length(btrim(name_ru)) > 0),
    name_kk varchar(120) NOT NULL CHECK (length(btrim(name_kk)) > 0),
    name_en varchar(120) NOT NULL CHECK (length(btrim(name_en)) > 0),
    icon varchar(40) NOT NULL CHECK (icon ~ '^[a-z][a-z0-9_]{1,39}$'),
    -- Shown on the Beauty home grid (8 tiles + «Ещё»); the rest open from «Ещё».
    featured boolean NOT NULL DEFAULT false,
    active boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO marketplace.beauty_categories (code, name_ru, name_kk, name_en, icon, featured, sort_order) VALUES
    ('SALONS', 'Салоны', 'Салондар', 'Salons', 'storefront', true, 10),
    ('BARBERSHOPS', 'Барбершопы', 'Барбершоптар', 'Barbershops', 'content_cut', true, 20),
    ('MANICURE', 'Маникюр', 'Маникюр', 'Manicure', 'back_hand', true, 30),
    ('COSMETOLOGY', 'Косметология', 'Косметология', 'Cosmetology', 'face_retouching_natural', true, 40),
    ('MASSAGE', 'Массаж', 'Массаж', 'Massage', 'self_improvement', true, 50),
    ('SPA', 'СПА', 'СПА', 'Spa', 'spa', true, 60),
    ('HAIR', 'Волосы', 'Шаш', 'Hair', 'brush', true, 70),
    ('BROWS_LASHES', 'Брови и ресницы', 'Қас және кірпік', 'Brows and lashes', 'visibility', true, 80),
    ('MAKEUP', 'Макияж', 'Макияж', 'Makeup', 'palette', false, 90),
    ('EPILATION', 'Эпиляция', 'Эпиляция', 'Hair removal', 'auto_fix_high', false, 100),
    ('TATTOO_PIERCING', 'Тату и пирсинг', 'Татуировка және пирсинг', 'Tattoo and piercing', 'brush', false, 110),
    ('WELLNESS', 'Велнес', 'Велнес', 'Wellness', 'favorite', false, 120);
