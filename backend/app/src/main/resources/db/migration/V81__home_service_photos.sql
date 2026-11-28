-- Only metadata is stored here. Booking-owned subjects are resolved through the Booking module.
CREATE TABLE marketplace.home_service_photos (
    id uuid PRIMARY KEY,
    subject_type text NOT NULL CHECK (subject_type IN ('BOOKING', 'OFFER', 'REVIEW')),
    subject_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    city_id uuid,
    partner_id uuid,
    uploaded_by uuid NOT NULL,
    purpose text NOT NULL,
    idempotency_key uuid NOT NULL,
    content_sha256 bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
    content_type text NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png')),
    byte_size integer NOT NULL CHECK (byte_size BETWEEN 1 AND 8388608),
    width integer NOT NULL CHECK (width BETWEEN 1 AND 6000),
    height integer NOT NULL CHECK (height BETWEEN 1 AND 6000),
    state text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'READY', 'DELETED')),
    moderation text NOT NULL CHECK (moderation IN ('PRIVATE', 'PENDING', 'PUBLISHED', 'HIDDEN')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    object_removed_at timestamptz,
    UNIQUE (subject_type, subject_id, uploaded_by, idempotency_key),
    CHECK (width * height <= 12000000),
    CHECK (object_removed_at IS NULL OR state = 'DELETED'),
    CHECK (
        (subject_type = 'BOOKING' AND purpose IN ('PROBLEM', 'BEFORE', 'AFTER', 'EXTRA') AND moderation = 'PRIVATE')
        OR (subject_type = 'OFFER' AND purpose = 'GALLERY' AND moderation <> 'PRIVATE')
        OR (subject_type = 'REVIEW' AND purpose = 'REVIEW' AND moderation <> 'PRIVATE')
    )
);

CREATE INDEX home_service_photos_subject_idx ON marketplace.home_service_photos (subject_type, subject_id, created_at, id)
    WHERE state IN ('PENDING', 'READY');
CREATE INDEX home_service_photos_cleanup_idx ON marketplace.home_service_photos (updated_at, id)
    WHERE state IN ('PENDING', 'DELETED') AND object_removed_at IS NULL;

CREATE TABLE marketplace.home_service_photo_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    photo_id uuid NOT NULL REFERENCES marketplace.home_service_photos(id),
    actor_id uuid NOT NULL,
    action text NOT NULL CHECK (action IN ('UPLOAD', 'DELETE', 'PUBLISH', 'HIDE')),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
