-- Home services (cleaning) reuse the Booking mechanism: venue category CLEANING already exists (V18). A "master" is a
-- synthetic cleaning crew, slots/conflict protection/cancellation are unchanged. Extensions are minimal:
--  * services may be priced by area: price = price_minor (call-out) + price_per_sqm_minor * area, area limited to a range;
--  * a booking stores its category, the customer's address and the area. Existing barbershop bookings keep category BARBER
--    with no address/area (backward compatible).
ALTER TABLE marketplace.booking_services
    ADD COLUMN price_per_sqm_minor bigint NOT NULL DEFAULT 0 CHECK (price_per_sqm_minor >= 0),
    ADD COLUMN min_area_sqm integer,
    ADD COLUMN max_area_sqm integer,
    ADD CONSTRAINT booking_services_area_pricing CHECK (
        (price_per_sqm_minor = 0 AND min_area_sqm IS NULL AND max_area_sqm IS NULL)
        OR (price_per_sqm_minor > 0 AND min_area_sqm >= 1 AND max_area_sqm >= min_area_sqm AND max_area_sqm <= 1000));

ALTER TABLE transactions.bookings
    ADD COLUMN category varchar(16) COLLATE "C" NOT NULL DEFAULT 'BARBER' CHECK (category IN ('BARBER', 'CLEANING')),
    ADD COLUMN address_text varchar(300),
    ADD COLUMN area_sqm integer,
    ADD CONSTRAINT bookings_home_details CHECK (
        (category = 'CLEANING' AND address_text IS NOT NULL AND length(btrim(address_text)) > 0
            AND (area_sqm IS NULL OR area_sqm BETWEEN 1 AND 1000))
        OR (category <> 'CLEANING' AND address_text IS NULL AND area_sqm IS NULL));
