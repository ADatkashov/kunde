-- KUNDE Groceries 1.0 (DEV pilot): product categories, richer product attributes, favorite products, shopping lists,
-- server-side cart and the GROCERIES feature switch. Stores and products still live in the Food tables
-- (vertical = 'GROCERY'); orders, promotions, stock reservation and substitutions are reused from Food.

-- ---- feature switch ------------------------------------------------------------------------------------
ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'GROCERIES'));
ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'GROCERIES'));

-- ---- reference taxonomy (not demo data) ------------------------------------------------------------------
CREATE TABLE marketplace.grocery_categories (
    slug varchar(32) COLLATE "C" PRIMARY KEY CHECK (slug ~ '^[a-z0-9_]{2,32}$'),
    name_ru varchar(80) NOT NULL,
    name_kk varchar(80) NOT NULL,
    name_en varchar(80) NOT NULL,
    icon varchar(32) NOT NULL,
    sort_order integer NOT NULL,
    enabled boolean NOT NULL DEFAULT true
);
INSERT INTO marketplace.grocery_categories (slug, name_ru, name_kk, name_en, icon, sort_order) VALUES
    ('fruit_veg', 'Овощи и фрукты', 'Көкөніс және жеміс', 'Fruit & vegetables', 'eco', 10),
    ('dairy', 'Молочные продукты', 'Сүт өнімдері', 'Dairy', 'water_drop', 20),
    ('meat', 'Мясо и птица', 'Ет және құс еті', 'Meat & poultry', 'set_meal', 30),
    ('fish', 'Рыба и морепродукты', 'Балық және теңіз өнімдері', 'Fish & seafood', 'phishing', 40),
    ('bakery', 'Хлеб и выпечка', 'Нан және тоқаш', 'Bread & bakery', 'bakery_dining', 50),
    ('drinks', 'Напитки', 'Сусындар', 'Drinks', 'local_drink', 60),
    ('pantry', 'Бакалея', 'Бакалея', 'Pantry', 'rice_bowl', 70),
    ('sweets', 'Сладости', 'Тәттілер', 'Sweets & snacks', 'cookie', 80),
    ('frozen', 'Замороженные продукты', 'Мұздатылған өнімдер', 'Frozen', 'ac_unit', 90),
    ('ready_meals', 'Готовая еда', 'Дайын тағам', 'Ready meals', 'lunch_dining', 100),
    ('household', 'Бытовая химия и дом', 'Тұрмыстық химия және үй', 'Household', 'cleaning_services', 110),
    ('kids', 'Детские товары', 'Балалар тауарлары', 'Kids', 'child_care', 120);

-- ---- product attributes ----------------------------------------------------------------------------------
ALTER TABLE marketplace.food_dishes
    ADD COLUMN grocery_category varchar(32) COLLATE "C" REFERENCES marketplace.grocery_categories(slug),
    ADD COLUMN brand varchar(80),
    ADD COLUMN origin_country varchar(60),
    ADD COLUMN composition varchar(500),
    ADD COLUMN storage_conditions varchar(300),
    ADD COLUMN kcal_100 integer CHECK (kcal_100 IS NULL OR kcal_100 BETWEEN 0 AND 1000),
    ADD COLUMN protein_100 numeric(5, 1) CHECK (protein_100 IS NULL OR protein_100 BETWEEN 0 AND 100),
    ADD COLUMN fat_100 numeric(5, 1) CHECK (fat_100 IS NULL OR fat_100 BETWEEN 0 AND 100),
    ADD COLUMN carbs_100 numeric(5, 1) CHECK (carbs_100 IS NULL OR carbs_100 BETWEEN 0 AND 100),
    ADD COLUMN compare_at_price_minor bigint,
    ADD COLUMN created_at timestamptz NOT NULL DEFAULT now(),
    ADD CONSTRAINT food_dishes_compare_at_ck CHECK (compare_at_price_minor IS NULL OR compare_at_price_minor > price_minor);
-- Existing rows have no known creation time: they are not "new".
UPDATE marketplace.food_dishes SET created_at = now() - interval '90 days';
CREATE INDEX food_order_items_dish_idx ON transactions.food_order_items (dish_id);
CREATE INDEX food_dishes_grocery_category_idx ON marketplace.food_dishes (grocery_category) WHERE grocery_category IS NOT NULL;

-- ---- favorite products ----------------------------------------------------------------------------------
CREATE TABLE marketplace.grocery_favorites (
    user_id uuid NOT NULL REFERENCES identity.users(id),
    dish_id uuid NOT NULL REFERENCES marketplace.food_dishes(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, dish_id)
);

-- ---- shopping lists (saved on the server) ------------------------------------------------------------------
CREATE TABLE marketplace.grocery_lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    name varchar(60) NOT NULL CHECK (length(btrim(name)) > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX grocery_lists_user_idx ON marketplace.grocery_lists (user_id, updated_at DESC);

CREATE TABLE marketplace.grocery_list_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_id uuid NOT NULL REFERENCES marketplace.grocery_lists(id),
    dish_id uuid NOT NULL REFERENCES marketplace.food_dishes(id),
    quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 10000),
    checked boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (list_id, dish_id)
);

-- ---- server-side cart (one per customer; prices are recomputed by the quote, never stored) -------------------
CREATE TABLE marketplace.grocery_carts (
    user_id uuid PRIMARY KEY REFERENCES identity.users(id),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    items jsonb NOT NULL CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) <= 30),
    updated_at timestamptz NOT NULL DEFAULT now()
);
