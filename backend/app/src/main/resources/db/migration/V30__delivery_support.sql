ALTER TABLE transactions.deliveries ADD CONSTRAINT deliveries_owner_id_unique UNIQUE (user_id, id);
ALTER TABLE support.cases ADD COLUMN delivery_id uuid;
ALTER TABLE support.cases ADD CONSTRAINT support_case_owned_delivery
    FOREIGN KEY (owner_user_id, delivery_id) REFERENCES transactions.deliveries (user_id, id);
ALTER TABLE support.cases ADD CONSTRAINT support_case_single_transaction
    CHECK (num_nonnulls(ride_id, delivery_id) <= 1);
CREATE INDEX support_cases_delivery_queue ON support.cases (created_at DESC, id) WHERE delivery_id IS NOT NULL;
