-- KUNDE Food MVP (DEV pilot). Restaurants/menus live in marketplace, orders in transactions.
-- Prices are integer minor units of KZT (D-04 DEV pilot: one final price, pay on receipt, 0% commission).
-- No rows are seeded here: synthetic demo restaurants come from the guarded DEV seeder (app.food.seed-demo).

CREATE TABLE marketplace.food_restaurants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug varchar(64) COLLATE "C" NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]*$'),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    cuisine varchar(80) NOT NULL CHECK (length(btrim(cuisine)) > 0),
    description varchar(500) NOT NULL DEFAULT '',
    emoji varchar(16) NOT NULL DEFAULT '🍽️',
    tone varchar(16) NOT NULL DEFAULT 'orange',
    delivery_fee_minor bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_minor >= 0),
    min_order_minor bigint NOT NULL DEFAULT 0 CHECK (min_order_minor >= 0),
    eta_min_minutes integer NOT NULL DEFAULT 30 CHECK (eta_min_minutes > 0),
    eta_max_minutes integer NOT NULL DEFAULT 45 CHECK (eta_max_minutes >= eta_min_minutes),
    is_open boolean NOT NULL DEFAULT true,
    is_synthetic boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE marketplace.food_menu_sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX food_menu_sections_restaurant_idx ON marketplace.food_menu_sections (restaurant_id, sort_order);

CREATE TABLE marketplace.food_dishes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    section_id uuid NOT NULL REFERENCES marketplace.food_menu_sections(id),
    name varchar(160) NOT NULL CHECK (length(btrim(name)) > 0),
    description varchar(500) NOT NULL DEFAULT '',
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    emoji varchar(16) NOT NULL DEFAULT '🍽️',
    tone varchar(16) NOT NULL DEFAULT 'orange',
    available boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX food_dishes_restaurant_idx ON marketplace.food_dishes (restaurant_id, section_id, sort_order);

CREATE TABLE marketplace.food_option_groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dish_id uuid NOT NULL REFERENCES marketplace.food_dishes(id),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    min_select integer NOT NULL DEFAULT 0 CHECK (min_select >= 0),
    max_select integer NOT NULL DEFAULT 1 CHECK (max_select >= 1 AND max_select >= min_select),
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX food_option_groups_dish_idx ON marketplace.food_option_groups (dish_id, sort_order);

CREATE TABLE marketplace.food_options (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id uuid NOT NULL REFERENCES marketplace.food_option_groups(id),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    price_delta_minor bigint NOT NULL DEFAULT 0 CHECK (price_delta_minor >= 0),
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0)
);
CREATE INDEX food_options_group_idx ON marketplace.food_options (group_id, sort_order);

CREATE TABLE transactions.food_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    restaurant_name varchar(120) NOT NULL,
    status varchar(24) COLLATE "C" NOT NULL DEFAULT 'PLACED'
        CHECK (status IN ('PLACED', 'ACCEPTED', 'PREPARING', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED')),
    payment_method varchar(16) COLLATE "C" NOT NULL CHECK (payment_method IN ('TEST_CARD', 'CASH_ON_DELIVERY')),
    payment_status varchar(16) COLLATE "C" NOT NULL CHECK (payment_status IN ('TEST_PAID', 'PAY_ON_RECEIPT', 'VOIDED')),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    subtotal_minor bigint NOT NULL CHECK (subtotal_minor >= 0),
    delivery_fee_minor bigint NOT NULL CHECK (delivery_fee_minor >= 0),
    total_minor bigint NOT NULL CHECK (total_minor = subtotal_minor + delivery_fee_minor),
    address_label varchar(80) NOT NULL,
    address_text varchar(500) NOT NULL,
    comment varchar(300),
    idempotency_key varchar(64) NOT NULL,
    placed_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT food_orders_idempotency UNIQUE (user_id, idempotency_key)
);
CREATE INDEX food_orders_user_idx ON transactions.food_orders (user_id, placed_at DESC, id);

CREATE TABLE transactions.food_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES transactions.food_orders(id),
    dish_id uuid NOT NULL REFERENCES marketplace.food_dishes(id),
    dish_name varchar(160) NOT NULL,
    options_text varchar(500) NOT NULL DEFAULT '',
    option_ids uuid[] NOT NULL DEFAULT '{}',
    unit_price_minor bigint NOT NULL CHECK (unit_price_minor >= 0),
    quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 20),
    line_total_minor bigint NOT NULL CHECK (line_total_minor = unit_price_minor * quantity)
);
CREATE INDEX food_order_items_order_idx ON transactions.food_order_items (order_id);

CREATE TABLE transactions.food_order_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES transactions.food_orders(id),
    status varchar(24) COLLATE "C" NOT NULL
        CHECK (status IN ('PLACED', 'ACCEPTED', 'PREPARING', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED')),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX food_order_events_order_idx ON transactions.food_order_events (order_id, id);

CREATE FUNCTION transactions.reject_food_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'integrity_constraint_violation';
END;
$$;
CREATE TRIGGER food_order_events_immutable BEFORE UPDATE OR DELETE ON transactions.food_order_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
