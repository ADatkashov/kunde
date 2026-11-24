-- Groceries: several photos per product (HTTPS URLs supplied by the partner; no file storage provider is connected).
-- The first photo (by sort_order) is mirrored into food_dishes.image_url, which stays the cover used by lists.
CREATE TABLE marketplace.food_dish_photos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dish_id uuid NOT NULL REFERENCES marketplace.food_dishes(id),
    url varchar(500) NOT NULL CHECK (url ~ '^https://[^ ]+$'),
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX food_dish_photos_dish_idx ON marketplace.food_dish_photos (dish_id, sort_order, created_at);
