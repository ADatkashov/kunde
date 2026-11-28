-- Home Services H6: verified reviews. A review belongs to one COMPLETED order of its author (booking_id is unique), carries an overall
-- rating and optional quality / punctuality ratings, and is published at once; staff can hide it (moderation) after a complaint.
-- Ratings shown anywhere are always computed from PUBLISHED reviews: no rating is stored or invented.
-- Order, service, venue, master, partner and user are referenced by id WITHOUT foreign keys (Constitution §5: no new constraints across
-- table owners); the service checks them under the order. partner_id is stored for tenant isolation of Partner reads.
CREATE TABLE marketplace.home_service_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id uuid NOT NULL UNIQUE,
    service_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    partner_id uuid NOT NULL,
    master_id uuid NOT NULL,
    user_id uuid NOT NULL,
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    quality_rating smallint CHECK (quality_rating BETWEEN 1 AND 5),
    punctuality_rating smallint CHECK (punctuality_rating BETWEEN 1 AND 5),
    comment varchar(1000),
    author_name varchar(60) NOT NULL DEFAULT 'Клиент',
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'PUBLISHED' CHECK (status IN ('PUBLISHED', 'HIDDEN')),
    moderation_note varchar(200),
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX home_service_reviews_service_idx ON marketplace.home_service_reviews (service_id, created_at DESC) WHERE status = 'PUBLISHED';
CREATE INDEX home_service_reviews_master_idx ON marketplace.home_service_reviews (master_id, created_at DESC) WHERE status = 'PUBLISHED';
CREATE INDEX home_service_reviews_partner_idx ON marketplace.home_service_reviews (partner_id, created_at DESC);
CREATE INDEX home_service_reviews_status_idx ON marketplace.home_service_reviews (status, created_at DESC);

-- A partner's complaint about a review; one per reporter and review. Resolved by staff, optionally hiding the review.
CREATE TABLE marketplace.home_service_review_complaints (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id uuid NOT NULL REFERENCES marketplace.home_service_reviews(id),
    partner_id uuid NOT NULL,
    reporter_user_id uuid NOT NULL,
    reason varchar(300) NOT NULL CHECK (length(btrim(reason)) >= 3),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED')),
    resolution varchar(300),
    resolved_by uuid,
    resolved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (review_id, reporter_user_id),
    CONSTRAINT home_service_review_complaints_resolved CHECK ((status = 'RESOLVED') = (resolved_at IS NOT NULL))
);
CREATE INDEX home_service_review_complaints_status_idx ON marketplace.home_service_review_complaints (status, created_at);

-- Append-only audit of everything that happens to a review.
CREATE TABLE marketplace.home_service_review_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    review_id uuid NOT NULL REFERENCES marketplace.home_service_reviews(id),
    actor_user_id uuid NOT NULL,
    actor_type varchar(10) COLLATE "C" NOT NULL CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'ADMIN')),
    action varchar(16) COLLATE "C" NOT NULL CHECK (action IN ('CREATED', 'COMPLAINT', 'HIDDEN', 'PUBLISHED', 'COMPLAINT_DONE')),
    note varchar(300),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX home_service_review_events_review_idx ON marketplace.home_service_review_events (review_id, id);
CREATE TRIGGER home_service_review_events_immutable
    BEFORE UPDATE OR DELETE ON marketplace.home_service_review_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
