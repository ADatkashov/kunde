-- Flowers & Gifts catalogue (ADR-026 step 2). The domain gets its own tables; rows of the old Food vertical FLOWERS_GIFTS are
-- COPIED here with the same ids, so existing links (orders, favourites) stay valid. Nothing is deleted from food_* in this step.
-- Prices are integer minor units of KZT. Photos are HTTPS links only (no file storage yet).

CREATE TABLE marketplace.flowers_categories (
    code varchar(32) COLLATE "C" PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,31}$'),
    name_ru varchar(120) NOT NULL CHECK (length(btrim(name_ru)) > 0),
    name_kk varchar(120) NOT NULL CHECK (length(btrim(name_kk)) > 0),
    name_en varchar(120) NOT NULL CHECK (length(btrim(name_en)) > 0),
    icon varchar(48) NOT NULL DEFAULT 'local_florist',
    featured boolean NOT NULL DEFAULT true,
    active boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);

INSERT INTO marketplace.flowers_categories (code, name_ru, name_kk, name_en, icon, featured, sort_order) VALUES
    ('BOUQUETS', 'Букеты', 'Гүл шоқтары', 'Bouquets', 'local_florist', true, 10),
    ('BOXED', 'Цветы в коробке', 'Қорапшадағы гүлдер', 'Boxed flowers', 'inventory_2', true, 20),
    ('COMPOSITIONS', 'Композиции', 'Композициялар', 'Arrangements', 'spa', true, 30),
    ('GIFTS', 'Подарки', 'Сыйлықтар', 'Gifts', 'card_giftcard', true, 40),
    ('SWEETS', 'Сладости', 'Тәттілер', 'Sweets', 'cake', true, 50),
    ('TOYS', 'Мягкие игрушки', 'Жұмсақ ойыншықтар', 'Soft toys', 'toys', true, 60),
    ('CARDS', 'Открытки', 'Ашықхаттар', 'Cards', 'mail', true, 70),
    ('OTHER', 'Ещё', 'Тағы', 'More', 'more_horiz', false, 80);

CREATE TABLE marketplace.flowers_shops (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug varchar(64) COLLATE "C" NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]*$'),
    partner_id uuid REFERENCES marketplace.partners(id),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    description varchar(500) NOT NULL DEFAULT '',
    emoji varchar(16) NOT NULL DEFAULT '💐',
    tone varchar(16) NOT NULL DEFAULT 'red',
    image_url varchar(500) CHECK (image_url IS NULL OR image_url ~ '^https://'),
    delivery_fee_minor bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_minor >= 0),
    min_order_minor bigint NOT NULL DEFAULT 0 CHECK (min_order_minor >= 0),
    eta_min_minutes integer NOT NULL DEFAULT 30 CHECK (eta_min_minutes > 0),
    eta_max_minutes integer NOT NULL DEFAULT 60 CHECK (eta_max_minutes >= eta_min_minutes),
    is_open boolean NOT NULL DEFAULT true,
    is_synthetic boolean NOT NULL DEFAULT false,
    latitude numeric(9, 6) CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9, 6) CHECK (longitude BETWEEN -180 AND 180),
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX flowers_shops_partner_idx ON marketplace.flowers_shops (partner_id) WHERE partner_id IS NOT NULL;
-- Placement key (V67 convention): nullable until backfilled, immutable once assigned.
ALTER TABLE marketplace.flowers_shops ADD COLUMN city_id uuid REFERENCES serviceability.cities(id);
CREATE INDEX flowers_shops_city_idx ON marketplace.flowers_shops (city_id) WHERE city_id IS NOT NULL;
CREATE TRIGGER flowers_shops_city_immutable BEFORE UPDATE OF city_id ON marketplace.flowers_shops
    FOR EACH ROW EXECUTE FUNCTION serviceability.forbid_city_change();

CREATE TABLE marketplace.flowers_products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL REFERENCES marketplace.flowers_shops(id),
    category_code varchar(32) COLLATE "C" NOT NULL REFERENCES marketplace.flowers_categories(code),
    name varchar(160) NOT NULL CHECK (length(btrim(name)) > 0),
    description varchar(500) NOT NULL DEFAULT '',
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    emoji varchar(16) NOT NULL DEFAULT '💐',
    tone varchar(16) NOT NULL DEFAULT 'red',
    image_url varchar(500) CHECK (image_url IS NULL OR image_url ~ '^https://'),
    available boolean NOT NULL DEFAULT true,
    stock_qty integer CHECK (stock_qty IS NULL OR stock_qty >= 0),
    popular boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX flowers_products_shop_idx ON marketplace.flowers_products (shop_id, category_code, sort_order);
CREATE INDEX flowers_products_popular_idx ON marketplace.flowers_products (sort_order) WHERE popular AND available;

-- Copy of the existing Food vertical FLOWERS_GIFTS (same ids). Sections are mapped to categories by name.
INSERT INTO marketplace.flowers_shops (id, slug, partner_id, city_id, name, description, emoji, tone, image_url, delivery_fee_minor,
                                       min_order_minor, eta_min_minutes, eta_max_minutes, is_open, is_synthetic, latitude, longitude, sort_order, created_at)
SELECT r.id, r.slug, r.partner_id, r.city_id, r.name, r.description, r.emoji, r.tone, r.image_url, r.delivery_fee_minor,
       r.min_order_minor, r.eta_min_minutes, r.eta_max_minutes, r.is_open, r.is_synthetic, r.latitude, r.longitude, r.sort_order, r.created_at
FROM marketplace.food_restaurants r
WHERE r.vertical = 'FLOWERS_GIFTS';

INSERT INTO marketplace.flowers_products (id, shop_id, category_code, name, description, price_minor, emoji, tone, image_url, available, stock_qty, popular, sort_order)
SELECT d.id, d.restaurant_id,
       CASE
           WHEN lower(s.name) LIKE '%короб%' THEN 'BOXED'
           WHEN lower(s.name) LIKE '%композ%' THEN 'COMPOSITIONS'
           WHEN lower(s.name) LIKE '%букет%' OR lower(s.name) LIKE '%цвет%' THEN 'BOUQUETS'
           WHEN lower(s.name) LIKE '%подар%' OR lower(s.name) LIKE '%сувенир%' THEN 'GIFTS'
           WHEN lower(s.name) LIKE '%сладост%' OR lower(s.name) LIKE '%конфет%' THEN 'SWEETS'
           WHEN lower(s.name) LIKE '%игруш%' THEN 'TOYS'
           WHEN lower(s.name) LIKE '%открыт%' THEN 'CARDS'
           ELSE 'OTHER'
       END,
       d.name, d.description, d.price_minor, d.emoji, d.tone, d.image_url, d.available, d.stock_qty, false, d.sort_order
FROM marketplace.food_dishes d
JOIN marketplace.food_menu_sections s ON s.id = d.section_id
JOIN marketplace.food_restaurants r ON r.id = d.restaurant_id
WHERE r.vertical = 'FLOWERS_GIFTS';
