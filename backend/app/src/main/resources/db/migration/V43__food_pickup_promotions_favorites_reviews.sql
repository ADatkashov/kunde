-- KUNDE Food 2.0 (DEV pilot): pickup, promotions/promo codes, favorites, verified reviews, audit.
-- Money stays integer KZT minor units. Discounts are always computed on the server.

-- ---- pickup + discount on orders ------------------------------------------------------------------
ALTER TABLE marketplace.food_restaurants
    ADD COLUMN pickup_enabled boolean NOT NULL DEFAULT true,
    ADD COLUMN address_text varchar(300),
    ADD COLUMN prep_minutes integer NOT NULL DEFAULT 20 CHECK (prep_minutes BETWEEN 1 AND 240);

ALTER TABLE transactions.food_orders
    ADD COLUMN fulfillment_type varchar(12) COLLATE "C" NOT NULL DEFAULT 'DELIVERY'
        CONSTRAINT food_orders_fulfillment_type_check CHECK (fulfillment_type IN ('DELIVERY', 'PICKUP')),
    ADD COLUMN discount_minor bigint NOT NULL DEFAULT 0 CONSTRAINT food_orders_discount_check CHECK (discount_minor >= 0),
    ADD COLUMN promo_code varchar(32);

ALTER TABLE transactions.food_orders DROP CONSTRAINT food_orders_check;
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_total_check
    CHECK (total_minor = subtotal_minor + delivery_fee_minor - discount_minor AND discount_minor <= subtotal_minor + delivery_fee_minor);
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_pickup_fee_check
    CHECK (fulfillment_type = 'DELIVERY' OR delivery_fee_minor = 0);

ALTER TABLE transactions.food_orders DROP CONSTRAINT food_orders_status_check;
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_status_check
    CHECK (status IN ('PLACED', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED'));
ALTER TABLE transactions.food_order_events DROP CONSTRAINT food_order_events_status_check;
ALTER TABLE transactions.food_order_events ADD CONSTRAINT food_order_events_status_check
    CHECK (status IN ('PLACED', 'ACCEPTED', 'PREPARING', 'READY_FOR_PICKUP', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED'));

-- ---- promotions --------------------------------------------------------------------------------------
CREATE TABLE marketplace.food_promotions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(32) COLLATE "C" CHECK (code IS NULL OR code ~ '^[A-Z0-9_-]{3,32}$'),
    title varchar(120) NOT NULL CHECK (length(btrim(title)) > 0),
    description varchar(300) NOT NULL DEFAULT '',
    kind varchar(8) COLLATE "C" NOT NULL CHECK (kind IN ('PERCENT', 'FIXED')),
    value bigint NOT NULL CHECK (value > 0),
    max_discount_minor bigint CHECK (max_discount_minor IS NULL OR max_discount_minor > 0),
    min_subtotal_minor bigint NOT NULL DEFAULT 0 CHECK (min_subtotal_minor >= 0),
    restaurant_id uuid REFERENCES marketplace.food_restaurants(id),
    cuisine varchar(80),
    owner_partner_id uuid REFERENCES marketplace.partners(id),
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz NOT NULL,
    max_redemptions integer CHECK (max_redemptions IS NULL OR max_redemptions > 0),
    per_user_limit integer NOT NULL DEFAULT 1 CHECK (per_user_limit BETWEEN 1 AND 100),
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PAUSED', 'DISABLED')),
    banner boolean NOT NULL DEFAULT false,
    is_synthetic boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (kind <> 'PERCENT' OR value <= 100),
    CHECK (ends_at > starts_at)
);
CREATE UNIQUE INDEX food_promotions_code_idx ON marketplace.food_promotions (code) WHERE code IS NOT NULL;
CREATE INDEX food_promotions_restaurant_idx ON marketplace.food_promotions (restaurant_id, status, ends_at);

CREATE TABLE transactions.food_promo_redemptions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_id uuid NOT NULL REFERENCES marketplace.food_promotions(id),
    order_id uuid NOT NULL UNIQUE REFERENCES transactions.food_orders(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    discount_minor bigint NOT NULL CHECK (discount_minor > 0),
    redeemed_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz
);
CREATE INDEX food_promo_redemptions_user_idx ON transactions.food_promo_redemptions (promotion_id, user_id) WHERE released_at IS NULL;

-- ---- favorites ---------------------------------------------------------------------------------------
CREATE TABLE marketplace.food_favorites (
    user_id uuid NOT NULL REFERENCES identity.users(id),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, restaurant_id)
);

-- ---- verified reviews (one per delivered order) -------------------------------------------------------
CREATE TABLE marketplace.food_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL UNIQUE REFERENCES transactions.food_orders(id),
    restaurant_id uuid NOT NULL REFERENCES marketplace.food_restaurants(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment varchar(1000),
    author_name varchar(60) NOT NULL DEFAULT 'Гость',
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'VISIBLE' CHECK (status IN ('VISIBLE', 'HIDDEN')),
    moderation_note varchar(200),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX food_reviews_restaurant_idx ON marketplace.food_reviews (restaurant_id, status, created_at DESC);

CREATE TABLE marketplace.food_review_complaints (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id uuid NOT NULL REFERENCES marketplace.food_reviews(id),
    reporter_user_id uuid NOT NULL REFERENCES identity.users(id),
    reason varchar(300) NOT NULL CHECK (length(btrim(reason)) >= 3),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (review_id, reporter_user_id)
);

-- ---- append-only audit of partner/admin changes ------------------------------------------------------
CREATE TABLE marketplace.food_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id uuid NOT NULL,
    actor_type varchar(10) COLLATE "C" NOT NULL CHECK (actor_type IN ('ADMIN', 'PARTNER', 'CUSTOMER')),
    action varchar(60) NOT NULL,
    target varchar(80) NOT NULL,
    detail varchar(300) NOT NULL DEFAULT '',
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER food_audit_immutable BEFORE UPDATE OR DELETE ON marketplace.food_audit
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

-- ---- admin permission for the Food control center --------------------------------------------------------
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS', 'FOOD_OPERATIONS'));

-- ---- moderation of restaurants and DEV test refunds ------------------------------------------------------
ALTER TABLE marketplace.food_restaurants
    ADD COLUMN moderation_status varchar(10) COLLATE "C" NOT NULL DEFAULT 'ACTIVE' CHECK (moderation_status IN ('ACTIVE', 'BLOCKED')),
    ADD COLUMN moderation_note varchar(200);

ALTER TABLE transactions.food_orders DROP CONSTRAINT food_orders_payment_status_check;
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_payment_status_check
    CHECK (payment_status IN ('TEST_PAID', 'PAY_ON_RECEIPT', 'VOIDED', 'NO_PAYMENT', 'REFUNDED'));
ALTER TABLE transactions.food_orders
    ADD COLUMN refunded_minor bigint NOT NULL DEFAULT 0 CONSTRAINT food_orders_refunded_check CHECK (refunded_minor >= 0 AND refunded_minor <= total_minor),
    ADD COLUMN refund_reason varchar(200);
