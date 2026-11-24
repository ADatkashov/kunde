-- TASK-037 / SUP-001. Consumer-owned support cases: contract foundation only.
-- Not linked to orders/bookings/payments (those domains are not enabled, ADR-014); no staff queue,
-- assignment, SLA timers or resolution workflow (roles D-14 and SLOs D-12 are unapproved).
CREATE TABLE support.cases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid NOT NULL REFERENCES identity.users(id),
    category varchar(32) COLLATE "C" NOT NULL
        CHECK (category IN ('GENERAL', 'ACCOUNT', 'PRIVACY', 'APP_PROBLEM')),
    message text NOT NULL
        CHECK (length(btrim(message)) > 0 AND length(message) <= 2000),
    status varchar(32) COLLATE "C" NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'ESCALATION_REQUESTED')),
    idempotency_key varchar(64) COLLATE "C" NOT NULL
        CHECK (idempotency_key ~ '^[A-Za-z0-9_-]{16,64}$'),
    request_sha256 varchar(64) COLLATE "C" NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (owner_user_id, idempotency_key)
);
CREATE INDEX cases_owner_created_idx ON support.cases (owner_user_id, created_at DESC, id);
-- Append-only history; rows are never updated or deleted by the application.
CREATE TABLE support.case_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    case_id uuid NOT NULL REFERENCES support.cases(id),
    event_type varchar(32) COLLATE "C" NOT NULL
        CHECK (event_type IN ('CREATED', 'ESCALATION_REQUESTED')),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX case_events_case_idx ON support.case_events (case_id, id);
