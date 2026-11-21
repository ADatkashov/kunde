-- Groceries: interactive picking. The store marks each line picked, missing or replaced; a replacement the customer did not
-- pre-approve is a PROPOSAL the customer accepts or declines before the order can leave the store.
ALTER TABLE transactions.food_order_items DROP CONSTRAINT food_order_items_fulfillment_ck;
ALTER TABLE transactions.food_order_items ADD CONSTRAINT food_order_items_fulfillment_ck
    CHECK (fulfillment_status IN ('PENDING', 'PROPOSED', 'OK', 'SUBSTITUTED', 'REMOVED'));
ALTER TABLE transactions.food_order_items DROP CONSTRAINT food_order_items_final_ck;
ALTER TABLE transactions.food_order_items ADD CONSTRAINT food_order_items_final_ck
    CHECK ((fulfillment_status IN ('PENDING', 'PROPOSED')) = (final_line_total_minor IS NULL));
ALTER TABLE transactions.food_order_items
    ADD COLUMN proposed_dish_id uuid REFERENCES marketplace.food_dishes(id),
    ADD COLUMN proposed_name varchar(160),
    ADD COLUMN proposed_unit_price_minor bigint CHECK (proposed_unit_price_minor IS NULL OR proposed_unit_price_minor >= 0),
    ADD CONSTRAINT food_order_items_proposal_ck CHECK ((fulfillment_status = 'PROPOSED') = (proposed_dish_id IS NOT NULL));
