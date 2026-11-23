-- ADR-022: transactional outbox and consumer inbox (expand-only; nothing writes here until a product opts in).
CREATE SCHEMA IF NOT EXISTS platform;

CREATE TABLE platform.outbox_events (
    seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    event_type varchar(120) COLLATE "C" NOT NULL CHECK (event_type ~ '^kunde\.[a-z0-9_]+\.[a-z0-9_]+$'),
    schema_version integer NOT NULL CHECK (schema_version >= 1),
    producer varchar(40) COLLATE "C" NOT NULL,
    aggregate_type varchar(60) COLLATE "C" NOT NULL,
    aggregate_id uuid NOT NULL,
    aggregate_version bigint CHECK (aggregate_version IS NULL OR aggregate_version >= 0),
    correlation_id varchar(64),
    causation_id uuid,
    -- Placement hint only (no foreign key): lets a consumer route by city without reading the aggregate.
    city_id uuid,
    payload jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    status varchar(16) COLLATE "C" NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'DELIVERED', 'DEAD')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    last_error varchar(500),
    delivered_at timestamptz,
    CHECK ((status = 'DELIVERED') = (delivered_at IS NOT NULL))
);
-- The relay scans only unfinished work; per-aggregate ordering lookups use the second index.
CREATE INDEX outbox_events_due_idx ON platform.outbox_events (next_attempt_at, seq) WHERE status = 'PENDING';
CREATE INDEX outbox_events_aggregate_idx ON platform.outbox_events (aggregate_type, aggregate_id, seq) WHERE status <> 'DELIVERED';

-- A consumer records every event it has handled; (consumer, event_id) makes at-least-once delivery idempotent.
CREATE TABLE platform.inbox_events (
    consumer varchar(80) COLLATE "C" NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (consumer, event_id)
);
