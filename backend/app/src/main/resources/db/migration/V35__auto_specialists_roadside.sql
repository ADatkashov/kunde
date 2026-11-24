-- KUNDE Auto: specialists (Executor specialisation AUTO_SPECIALIST) and on-site (roadside) jobs.
-- Separate from rides drivers and delivery couriers: an Auto approval gives no right to rides or deliveries and vice versa.
-- A specialist is approved per service category (only mobile categories), so permissions are explicit and auditable.

CREATE TABLE transactions.auto_specialists (
    user_id uuid PRIMARY KEY REFERENCES identity.users(id),
    display_name varchar(80) NOT NULL CHECK (length(btrim(display_name)) > 0),
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'BLOCKED')),
    online boolean NOT NULL DEFAULT false CHECK (NOT online OR status = 'APPROVED'),
    latitude numeric(9,6) CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9,6) CHECK (longitude BETWEEN -180 AND 180),
    observed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(latitude, longitude, observed_at) IN (0, 3)),
    CHECK (online OR observed_at IS NULL)
);

CREATE TABLE transactions.auto_specialist_categories (
    user_id uuid NOT NULL REFERENCES transactions.auto_specialists(user_id),
    category varchar(24) COLLATE "C" NOT NULL REFERENCES marketplace.auto_service_categories(code),
    PRIMARY KEY (user_id, category)
);

-- Append-only record of every admin decision about a specialist.
CREATE TABLE transactions.auto_specialist_reviews (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specialist_id uuid NOT NULL REFERENCES transactions.auto_specialists(user_id),
    reviewer_id uuid NOT NULL REFERENCES identity.users(id),
    decision varchar(12) COLLATE "C" NOT NULL CHECK (decision IN ('APPROVED', 'BLOCKED')),
    categories varchar(200) NOT NULL DEFAULT '',
    reason varchar(200) NOT NULL CHECK (length(btrim(reason)) > 0),
    occurred_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    CHECK (specialist_id <> reviewer_id)
);
CREATE TRIGGER auto_specialist_reviews_immutable BEFORE UPDATE OR DELETE ON transactions.auto_specialist_reviews
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

-- Platform tariff for on-site work: the price kind is FROM, the final price is proposed on site and approved by the customer.
CREATE TABLE marketplace.auto_roadside_tariffs (
    category varchar(24) COLLATE "C" PRIMARY KEY REFERENCES marketplace.auto_service_categories(code),
    base_price_minor bigint NOT NULL CHECK (base_price_minor >= 0)
);
INSERT INTO marketplace.auto_roadside_tariffs (category, base_price_minor)
    SELECT code, 1500000 FROM marketplace.auto_service_categories WHERE mobile;

CREATE TABLE transactions.auto_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    vehicle_id uuid NOT NULL REFERENCES transactions.customer_vehicles(id),
    vehicle_label varchar(120) NOT NULL,
    category varchar(24) COLLATE "C" NOT NULL REFERENCES marketplace.auto_service_categories(code),
    description varchar(300) NOT NULL DEFAULT '',
    address_text varchar(300) NOT NULL CHECK (length(btrim(address_text)) >= 5),
    latitude numeric(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'REQUESTED'
        CHECK (status IN ('REQUESTED', 'ASSIGNED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
    specialist_id uuid REFERENCES transactions.auto_specialists(user_id),
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    price_kind varchar(12) COLLATE "C" NOT NULL DEFAULT 'FROM',
    final_price_minor bigint CHECK (final_price_minor IS NULL OR final_price_minor >= 0),
    price_approval varchar(10) COLLATE "C" CHECK (price_approval IN ('PENDING', 'APPROVED', 'DECLINED')),
    idempotency_key varchar(64) NOT NULL,
    cancelled_by varchar(12) COLLATE "C" CHECK (cancelled_by IN ('CUSTOMER', 'SPECIALIST', 'SYSTEM')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0,
    CONSTRAINT auto_jobs_idempotency UNIQUE (user_id, idempotency_key),
    CONSTRAINT auto_jobs_assigned CHECK ((status = 'REQUESTED' OR status = 'CANCELLED') OR specialist_id IS NOT NULL),
    CONSTRAINT auto_jobs_not_self CHECK (specialist_id IS NULL OR specialist_id <> user_id)
);
-- One active job per customer car, one active job per specialist: a double accept is impossible at the database level.
CREATE UNIQUE INDEX auto_jobs_active_vehicle ON transactions.auto_jobs (vehicle_id)
    WHERE status IN ('REQUESTED', 'ASSIGNED', 'ARRIVED', 'IN_PROGRESS');
CREATE UNIQUE INDEX auto_jobs_active_specialist ON transactions.auto_jobs (specialist_id)
    WHERE status IN ('ASSIGNED', 'ARRIVED', 'IN_PROGRESS');
CREATE INDEX auto_jobs_user_idx ON transactions.auto_jobs (user_id, created_at DESC);
CREATE INDEX auto_jobs_open_idx ON transactions.auto_jobs (category, created_at) WHERE status = 'REQUESTED';

CREATE TABLE transactions.auto_job_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id uuid NOT NULL REFERENCES transactions.auto_jobs(id),
    status varchar(12) COLLATE "C" NOT NULL,
    actor_type varchar(12) COLLATE "C" NOT NULL CHECK (actor_type IN ('CUSTOMER', 'SPECIALIST', 'SYSTEM')),
    actor_user_id uuid REFERENCES identity.users(id),
    reason varchar(80),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auto_job_events_job_idx ON transactions.auto_job_events (job_id, id);
CREATE TRIGGER auto_job_events_immutable BEFORE UPDATE OR DELETE ON transactions.auto_job_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
