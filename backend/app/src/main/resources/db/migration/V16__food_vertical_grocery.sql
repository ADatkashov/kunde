-- Grocery MVP (DEV pilot) reuses the Food catalog/cart/order model: a store is a "restaurant" row and a product is a
-- "dish" row, distinguished by `vertical`. Existing rows stay FOOD. Same DEV-only gates as Food (FoodGuard).
ALTER TABLE marketplace.food_restaurants ADD COLUMN vertical varchar(16) COLLATE "C" NOT NULL DEFAULT 'FOOD'
    CHECK (vertical IN ('FOOD', 'GROCERY'));
CREATE INDEX food_restaurants_vertical_idx ON marketplace.food_restaurants (vertical, is_open DESC, sort_order, name);

ALTER TABLE transactions.food_orders ADD COLUMN vertical varchar(16) COLLATE "C" NOT NULL DEFAULT 'FOOD'
    CHECK (vertical IN ('FOOD', 'GROCERY'));
