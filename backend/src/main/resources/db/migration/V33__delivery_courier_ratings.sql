CREATE TABLE transactions.delivery_courier_ratings (
    delivery_id uuid PRIMARY KEY REFERENCES transactions.deliveries(id),
    stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
    created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
