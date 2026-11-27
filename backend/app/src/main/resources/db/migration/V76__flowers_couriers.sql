-- Flowers & Gifts courier hand-off (ADR-026 step 4). When a shop has assembled an order, an OPEN task appears for approved,
-- online couriers (the Delivery courier registry); one courier wins it atomically, pick-up and delivery move the order.
-- Pick-up address of a shop is shown to the courier before accepting; the customer's address only after acceptance.
ALTER TABLE marketplace.flowers_shops ADD COLUMN address_text varchar(300);
UPDATE marketplace.flowers_shops s SET address_text = r.address_text
FROM marketplace.food_restaurants r WHERE r.id = s.id AND r.address_text IS NOT NULL;

CREATE TABLE transactions.flowers_courier_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL UNIQUE REFERENCES transactions.flowers_orders(id),
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'ASSIGNED', 'PICKED_UP', 'DELIVERED', 'CANCELLED')),
    courier_id uuid REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    assigned_at timestamptz,
    picked_up_at timestamptz,
    delivered_at timestamptz,
    version bigint NOT NULL DEFAULT 1,
    CHECK (status NOT IN ('ASSIGNED', 'PICKED_UP', 'DELIVERED') OR courier_id IS NOT NULL)
);
CREATE INDEX flowers_courier_tasks_open_idx ON transactions.flowers_courier_tasks (created_at) WHERE status = 'OPEN';
CREATE INDEX flowers_courier_tasks_courier_idx ON transactions.flowers_courier_tasks (courier_id, status);
