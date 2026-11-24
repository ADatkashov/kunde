-- Expand existing DEV commerce constraints without changing Food or Grocery rows.
ALTER TABLE marketplace.food_restaurants DROP CONSTRAINT food_restaurants_vertical_check;
ALTER TABLE marketplace.food_restaurants ADD CONSTRAINT food_restaurants_vertical_check
    CHECK (vertical IN ('FOOD', 'GROCERY', 'FLOWERS_GIFTS'));
ALTER TABLE transactions.food_orders DROP CONSTRAINT food_orders_vertical_check;
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_vertical_check
    CHECK (vertical IN ('FOOD', 'GROCERY', 'FLOWERS_GIFTS'));
ALTER TABLE transactions.food_orders DROP CONSTRAINT food_orders_payment_method_check;
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_payment_method_check
    CHECK (payment_method IN ('TEST_CARD', 'CASH_ON_DELIVERY', 'DEV_NO_PAYMENT'));
ALTER TABLE transactions.food_orders DROP CONSTRAINT food_orders_payment_status_check;
ALTER TABLE transactions.food_orders ADD CONSTRAINT food_orders_payment_status_check
    CHECK (payment_status IN ('TEST_PAID', 'PAY_ON_RECEIPT', 'VOIDED', 'NO_PAYMENT'));
