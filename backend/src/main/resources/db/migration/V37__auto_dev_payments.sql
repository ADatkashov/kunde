-- KUNDE Auto DEV/TEST payment contract. No real provider, no card data, no real money: every amount is a ledger entry marked DEV_TEST.
-- Method PAY_ON_SITE keeps the existing "pay on receipt" model (no ledger movement). Method TEST_CARD simulates hold -> capture -> refund/void
-- so the booking and payment lifecycles can be tested end to end. Real payments stay disabled until an approved provider integration exists.

CREATE TABLE transactions.auto_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    booking_id uuid UNIQUE REFERENCES transactions.bookings(id),
    job_id uuid UNIQUE REFERENCES transactions.auto_jobs(id),
    method varchar(12) COLLATE "C" NOT NULL CHECK (method IN ('PAY_ON_SITE', 'TEST_CARD')),
    status varchar(20) COLLATE "C" NOT NULL CHECK (status IN ('PAY_ON_SITE', 'TEST_HELD', 'TEST_CAPTURED', 'TEST_VOIDED', 'TEST_REFUNDED', 'TEST_PART_REFUNDED')),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    held_minor bigint NOT NULL DEFAULT 0 CHECK (held_minor >= 0),
    captured_minor bigint NOT NULL DEFAULT 0 CHECK (captured_minor >= 0),
    refunded_minor bigint NOT NULL DEFAULT 0 CHECK (refunded_minor >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(booking_id, job_id) = 1),
    CHECK (refunded_minor <= captured_minor),
    CHECK (method = 'TEST_CARD' OR (held_minor = 0 AND captured_minor = 0 AND refunded_minor = 0 AND status = 'PAY_ON_SITE'))
);
CREATE INDEX auto_payments_status_idx ON transactions.auto_payments (status, updated_at DESC);

-- Append-only ledger of every simulated movement.
CREATE TABLE transactions.auto_payment_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id uuid NOT NULL REFERENCES transactions.auto_payments(id),
    kind varchar(12) COLLATE "C" NOT NULL CHECK (kind IN ('HOLD', 'CAPTURE', 'VOID', 'REFUND')),
    amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
    actor_type varchar(12) COLLATE "C" NOT NULL CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'SPECIALIST', 'ADMIN', 'SYSTEM')),
    actor_user_id uuid REFERENCES identity.users(id),
    reason varchar(200),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auto_payment_events_payment_idx ON transactions.auto_payment_events (payment_id, id);
CREATE TRIGGER auto_payment_events_immutable BEFORE UPDATE OR DELETE ON transactions.auto_payment_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
