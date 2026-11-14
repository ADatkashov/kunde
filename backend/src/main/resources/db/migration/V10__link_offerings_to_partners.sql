-- TASK-016 / D-07: an offering belongs to exactly one partner (docs/architecture/12-data-model.md).
-- Link only: no price, stock, availability or HTTP write API. DRAFT/SUSPENDED/RETIRED rows may stay
-- unlinked, but a PUBLISHED offering must reference a partner; it is shown to consumers only while that
-- partner is APPROVED (ADR-014 gates unchanged, catalog stays empty by default).
ALTER TABLE marketplace.offerings ADD COLUMN partner_id uuid REFERENCES marketplace.partners(id);
ALTER TABLE marketplace.offerings ADD CONSTRAINT offerings_published_has_partner
    CHECK (status <> 'PUBLISHED' OR partner_id IS NOT NULL);
CREATE INDEX offerings_partner_idx ON marketplace.offerings (partner_id, status);
