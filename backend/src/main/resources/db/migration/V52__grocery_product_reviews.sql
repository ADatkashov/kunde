-- Verified product reviews: only a customer whose delivered Groceries order contained the product can review it, once per order.
CREATE TABLE marketplace.grocery_product_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dish_id uuid NOT NULL REFERENCES marketplace.food_dishes(id),
    order_id uuid NOT NULL REFERENCES transactions.food_orders(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment varchar(1000),
    author_name varchar(60) NOT NULL DEFAULT 'Покупатель',
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'VISIBLE' CHECK (status IN ('VISIBLE', 'HIDDEN')),
    moderation_note varchar(200),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (order_id, dish_id)
);
CREATE INDEX grocery_product_reviews_dish_idx ON marketplace.grocery_product_reviews (dish_id, status, created_at DESC);
