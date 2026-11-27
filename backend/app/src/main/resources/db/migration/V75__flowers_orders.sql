-- Flowers & Gifts orders (ADR-026 step 3). Own tables, own lifecycle; payments stay disabled: DEV_NO_PAYMENT only.
-- Prices are integer minor units of KZT. The delivery address is copied into the order (a snapshot, like Food orders).

CREATE TABLE transactions.flowers_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    shop_id uuid NOT NULL REFERENCES marketplace.flowers_shops(id),
    shop_name varchar(120) NOT NULL,
    status varchar(24) COLLATE "C" NOT NULL DEFAULT 'PLACED'
        CHECK (status IN ('PLACED', 'ACCEPTED', 'ASSEMBLING', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED')),
    payment_method varchar(16) COLLATE "C" NOT NULL DEFAULT 'DEV_NO_PAYMENT' CHECK (payment_method = 'DEV_NO_PAYMENT'),
    payment_status varchar(16) COLLATE "C" NOT NULL DEFAULT 'NO_PAYMENT' CHECK (payment_status = 'NO_PAYMENT'),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    subtotal_minor bigint NOT NULL CHECK (subtotal_minor >= 0),
    delivery_fee_minor bigint NOT NULL CHECK (delivery_fee_minor >= 0),
    total_minor bigint NOT NULL CHECK (total_minor = subtotal_minor + delivery_fee_minor),
    delivery_mode varchar(12) COLLATE "C" NOT NULL CHECK (delivery_mode IN ('ASAP', 'SCHEDULED')),
    scheduled_from timestamptz,
    scheduled_to timestamptz,
    CONSTRAINT flowers_orders_window_ck CHECK (
        (delivery_mode = 'ASAP' AND scheduled_from IS NULL AND scheduled_to IS NULL)
        OR (delivery_mode = 'SCHEDULED' AND scheduled_from IS NOT NULL AND scheduled_to > scheduled_from)),
    address_label varchar(80) NOT NULL DEFAULT '',
    address_text varchar(500) NOT NULL CHECK (length(btrim(address_text)) >= 5),
    recipient_name varchar(80),
    card_text varchar(300),
    comment varchar(300),
    idempotency_key varchar(64) NOT NULL,
    placed_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT flowers_orders_idempotency UNIQUE (user_id, idempotency_key)
);
CREATE INDEX flowers_orders_user_idx ON transactions.flowers_orders (user_id, placed_at DESC, id);
CREATE INDEX flowers_orders_shop_idx ON transactions.flowers_orders (shop_id, status, placed_at DESC);

CREATE TABLE transactions.flowers_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES transactions.flowers_orders(id),
    product_id uuid NOT NULL REFERENCES marketplace.flowers_products(id),
    product_name varchar(160) NOT NULL,
    emoji varchar(16) NOT NULL DEFAULT '💐',
    unit_price_minor bigint NOT NULL CHECK (unit_price_minor >= 0),
    quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 20),
    line_total_minor bigint NOT NULL CHECK (line_total_minor = unit_price_minor * quantity)
);
CREATE INDEX flowers_order_items_order_idx ON transactions.flowers_order_items (order_id);

CREATE TABLE transactions.flowers_order_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES transactions.flowers_orders(id),
    status varchar(24) COLLATE "C" NOT NULL
        CHECK (status IN ('PLACED', 'ACCEPTED', 'ASSEMBLING', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED')),
    actor_type varchar(12) COLLATE "C" NOT NULL DEFAULT 'CUSTOMER' CHECK (actor_type IN ('CUSTOMER', 'SHOP', 'COURIER', 'SYSTEM')),
    actor_user_id uuid REFERENCES identity.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX flowers_order_events_order_idx ON transactions.flowers_order_events (order_id, id);

CREATE FUNCTION transactions.reject_flowers_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'integrity_constraint_violation';
END;
$$;
CREATE TRIGGER flowers_order_events_immutable BEFORE UPDATE OR DELETE ON transactions.flowers_order_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_flowers_event_mutation();
