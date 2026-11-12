-- TASK-009 / ADA-75. Storage contract only; no service zone is approved or enabled.
-- A location cannot be represented as serviceable merely because it was saved.
CREATE SCHEMA IF NOT EXISTS serviceability;

CREATE TABLE profile.consumer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    label varchar(80) NOT NULL CHECK (length(btrim(label)) > 0),
    formatted_address varchar(500) NOT NULL CHECK (length(btrim(formatted_address)) > 0),
    latitude numeric(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude numeric(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    deleted_at timestamptz,
    CONSTRAINT consumer_addresses_owner_id_unique UNIQUE (user_id, id)
);
CREATE INDEX consumer_addresses_active_owner_idx
    ON profile.consumer_addresses (user_id, created_at DESC) WHERE deleted_at IS NULL;

-- Zone configuration is deliberately non-serviceable by default. No default
-- Almaty polygon, geocoder, partner or production coverage is inferred.
CREATE TABLE serviceability.zones (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) COLLATE "C" NOT NULL UNIQUE CHECK (code ~ '^[a-z0-9][a-z0-9_-]*$'),
    enabled boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE serviceability.zone_addresses (
    zone_id uuid NOT NULL REFERENCES serviceability.zones(id),
    address_id uuid NOT NULL REFERENCES profile.consumer_addresses(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (zone_id, address_id)
);
CREATE INDEX zone_addresses_address_idx ON serviceability.zone_addresses (address_id);

-- Explicit membership alone does not authorize service. Only enabled zones
-- may be used by a future application-level serviceability check.
-- Membership insertion and zone enablement require a separately approved
-- operations contract; no public endpoint or background activation is added.
