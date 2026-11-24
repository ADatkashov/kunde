-- Groceries/Food courier hand-off: when a partner-owned DELIVERY order is ready, an OPEN task appears for approved, online
-- couriers (the same courier registry as Delivery). One courier wins the task atomically; pick-up and delivery move the order.
ALTER TABLE transactions.food_order_events DROP CONSTRAINT food_order_events_actor_type_check;
ALTER TABLE transactions.food_order_events ADD CONSTRAINT food_order_events_actor_type_check
    CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'SYSTEM', 'COURIER'));

CREATE TABLE transactions.food_courier_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL UNIQUE REFERENCES transactions.food_orders(id),
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
CREATE INDEX food_courier_tasks_open_idx ON transactions.food_courier_tasks (created_at) WHERE status = 'OPEN';
CREATE INDEX food_courier_tasks_courier_idx ON transactions.food_courier_tasks (courier_id, status);
