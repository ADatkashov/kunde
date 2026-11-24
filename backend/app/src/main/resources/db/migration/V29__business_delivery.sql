ALTER TABLE transactions.delivery_quotes ADD COLUMN partner_id uuid REFERENCES marketplace.partners(id);
ALTER TABLE transactions.deliveries ADD COLUMN partner_id uuid REFERENCES marketplace.partners(id);
CREATE INDEX deliveries_partner_history_idx ON transactions.deliveries(partner_id, created_at DESC, id DESC)
    WHERE partner_id IS NOT NULL;

-- Validate null-safe tenant equality against the quote in the same transaction.
CREATE FUNCTION transactions.check_delivery_quote_partner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM transactions.delivery_quotes q
        WHERE q.id = NEW.quote_id AND q.user_id = NEW.user_id
        AND q.partner_id IS NOT DISTINCT FROM NEW.partner_id) THEN
        RAISE EXCEPTION 'Delivery quote tenant mismatch';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER delivery_quote_partner_boundary BEFORE INSERT OR UPDATE OF quote_id, user_id, partner_id
    ON transactions.deliveries FOR EACH ROW EXECUTE FUNCTION transactions.check_delivery_quote_partner();
