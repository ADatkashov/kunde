-- D-01 (partially approved 2026-11-13): Food Ordering is the first category, Almaty the first market.
-- DRAFT only: not published, not searchable, not orderable (ADR-014 gates stay closed).
-- Publishing needs verified partners, serviceability and the payment/fulfillment decisions (D-02..D-08).
-- Names are working text, not reviewed copy (D-15).
INSERT INTO marketplace.categories (code, name_ru, name_kk, name_en, status, sort_order)
VALUES ('food-ordering', 'Заказ еды', 'Тамақ тапсырысы', 'Food ordering', 'DRAFT', 0)
ON CONFLICT (code) DO NOTHING;
