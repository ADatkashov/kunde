-- TASK-013 / EP-006. Catalog storage contract only: category tree and offering shell.
-- Nothing is published by default; no seed data, partner link, price, stock or availability is inferred.
-- Partner ownership, price model and availability rules need their own approved contracts (TASK-014/015).
CREATE TABLE marketplace.categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(64) COLLATE "C" NOT NULL UNIQUE CHECK (code ~ '^[a-z0-9][a-z0-9_-]*$'),
    parent_id uuid REFERENCES marketplace.categories(id),
    name_ru varchar(120) NOT NULL CHECK (length(btrim(name_ru)) > 0),
    name_kk varchar(120) NOT NULL CHECK (length(btrim(name_kk)) > 0),
    name_en varchar(120) CHECK (name_en IS NULL OR length(btrim(name_en)) > 0),
    status varchar(16) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'RETIRED')),
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT categories_not_own_parent CHECK (parent_id IS NULL OR parent_id <> id),
    CONSTRAINT categories_published_has_timestamp CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL)
);
CREATE INDEX categories_status_parent_idx ON marketplace.categories (status, parent_id, sort_order);

CREATE TABLE marketplace.offerings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id uuid NOT NULL REFERENCES marketplace.categories(id),
    kind varchar(16) NOT NULL CHECK (kind IN ('SERVICE', 'PRODUCT')),
    name_ru varchar(200) NOT NULL CHECK (length(btrim(name_ru)) > 0),
    name_kk varchar(200) NOT NULL CHECK (length(btrim(name_kk)) > 0),
    name_en varchar(200) CHECK (name_en IS NULL OR length(btrim(name_en)) > 0),
    status varchar(16) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'SUSPENDED', 'RETIRED')),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT offerings_published_has_timestamp CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL)
);
CREATE INDEX offerings_status_category_idx ON marketplace.offerings (status, category_id);
