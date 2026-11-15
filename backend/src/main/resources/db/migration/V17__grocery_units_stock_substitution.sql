-- Grocery completion (DEV pilot): weighed goods, stock limits, customer-controlled substitutions, optional photos.
-- Weighed goods (unit KG): price_minor is the price per kg and quantities are grams (step 100 g).
ALTER TABLE marketplace.food_dishes ADD COLUMN unit varchar(8) COLLATE "C" NOT NULL DEFAULT 'PIECE'
    CHECK (unit IN ('PIECE', 'KG'));
-- NULL = not tracked. Counted in pieces (PIECE) or grams (KG).
ALTER TABLE marketplace.food_dishes ADD COLUMN stock_qty integer CHECK (stock_qty IS NULL OR stock_qty >= 0);
ALTER TABLE marketplace.food_dishes ADD COLUMN image_url varchar(500) CHECK (image_url IS NULL OR image_url ~ '^https://');
ALTER TABLE marketplace.food_restaurants ADD COLUMN image_url varchar(500) CHECK (image_url IS NULL OR image_url ~ '^https://');

-- Order items: quantity becomes "pieces or grams"; re-create the table checks around that.
DO $$
DECLARE c record;
BEGIN
    FOR c IN SELECT conname FROM pg_constraint
             WHERE conrelid = 'transactions.food_order_items'::regclass AND contype = 'c' LOOP
        EXECUTE format('ALTER TABLE transactions.food_order_items DROP CONSTRAINT %I', c.conname);
    END LOOP;
END $$;

ALTER TABLE transactions.food_order_items
    ADD COLUMN line_no integer NOT NULL DEFAULT 0,
    ADD COLUMN unit varchar(8) COLLATE "C" NOT NULL DEFAULT 'PIECE',
    ADD COLUMN substitution varchar(12) COLLATE "C" NOT NULL DEFAULT 'NONE',
    ADD COLUMN substitute_dish_ids uuid[] NOT NULL DEFAULT '{}',
    ADD COLUMN fulfillment_status varchar(12) COLLATE "C" NOT NULL DEFAULT 'PENDING',
    ADD COLUMN replaced_by_dish_id uuid,
    ADD COLUMN replaced_by_name varchar(160),
    ADD COLUMN final_unit_price_minor bigint,
    ADD COLUMN final_line_total_minor bigint;

ALTER TABLE transactions.food_order_items
    ADD CONSTRAINT food_order_items_price_ck CHECK (unit_price_minor >= 0),
    ADD CONSTRAINT food_order_items_quantity_ck CHECK (quantity BETWEEN 1 AND 10000),
    ADD CONSTRAINT food_order_items_unit_ck CHECK (unit IN ('PIECE', 'KG')),
    ADD CONSTRAINT food_order_items_substitution_ck CHECK (substitution IN ('NONE', 'ANY_SIMILAR', 'CHOSEN')),
    ADD CONSTRAINT food_order_items_fulfillment_ck CHECK (fulfillment_status IN ('PENDING', 'OK', 'SUBSTITUTED', 'REMOVED')),
    ADD CONSTRAINT food_order_items_line_total_ck CHECK (
        (unit = 'PIECE' AND line_total_minor = unit_price_minor * quantity)
        OR (unit = 'KG' AND line_total_minor = (unit_price_minor * quantity + 500) / 1000)),
    ADD CONSTRAINT food_order_items_final_ck CHECK (
        (fulfillment_status = 'PENDING') = (final_line_total_minor IS NULL)),
    ADD CONSTRAINT food_order_items_replaced_ck CHECK (
        (fulfillment_status = 'SUBSTITUTED') = (replaced_by_name IS NOT NULL));

ALTER TABLE transactions.food_orders
    ADD COLUMN final_total_minor bigint CHECK (final_total_minor IS NULL OR final_total_minor >= 0),
    ADD COLUMN has_changes boolean NOT NULL DEFAULT false;
