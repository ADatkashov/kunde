CREATE TABLE transactions.health_favorites (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES identity.users(id),
    venue_id uuid REFERENCES marketplace.booking_venues(id),
    specialist_id uuid REFERENCES marketplace.booking_masters(id),
    service_id uuid REFERENCES marketplace.booking_services(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(venue_id, specialist_id, service_id) = 1),
    UNIQUE NULLS NOT DISTINCT (user_id, venue_id, specialist_id, service_id)
);

CREATE VIEW marketplace.health_favorite_targets AS
WITH public_venues AS (
    SELECT id, name FROM marketplace.booking_venues
    WHERE category = 'HEALTH' AND is_open AND is_synthetic AND health_published
)
SELECT 'ORGANIZATION' AS kind, id, id AS venue_id, name FROM public_venues
UNION ALL
SELECT 'SPECIALIST', m.id, m.venue_id, m.name
FROM marketplace.booking_masters m JOIN public_venues v ON v.id = m.venue_id
WHERE m.active
UNION ALL
SELECT 'WELLNESS_SERVICE', s.id, s.venue_id, s.name
FROM marketplace.booking_services s
JOIN public_venues v ON v.id = s.venue_id
JOIN marketplace.health_categories c ON c.code = s.health_category
WHERE s.available AND NOT c.medical;
