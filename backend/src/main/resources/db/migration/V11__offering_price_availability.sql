-- TASK-016 / D-04 (DEV pilot, 2026-11-14): one final price in KZT, minor units (tiyn); no KUNDE fee, service fee,
-- promo or tax columns. D-03: pay on receipt, nothing here collects money. Availability is a plain flag the partner
-- will own once the partner write API exists (blocked on ADR-018/D-14). A PUBLISHED offering must carry a price;
-- nothing is seeded, the public catalog stays empty by default (ADR-014).
ALTER TABLE marketplace.offerings ADD COLUMN price_minor bigint CHECK (price_minor IS NULL OR price_minor >= 0);
ALTER TABLE marketplace.offerings ADD COLUMN currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT');
ALTER TABLE marketplace.offerings ADD COLUMN availability varchar(16) NOT NULL DEFAULT 'UNAVAILABLE'
    CHECK (availability IN ('AVAILABLE', 'UNAVAILABLE'));
ALTER TABLE marketplace.offerings ADD CONSTRAINT offerings_published_has_price
    CHECK (status <> 'PUBLISHED' OR price_minor IS NOT NULL);
