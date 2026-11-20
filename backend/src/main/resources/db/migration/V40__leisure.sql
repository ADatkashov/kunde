-- KUNDE Leisure & Entertainment 1.0 (DEV/TEST): one common domain model for cinemas, bowling, karaoke, quests, concerts, excursions etc.
-- Five booking types share the same tables: TIME_SLOT (a resource for a time), CAPACITY (limited places), SEAT_MAP (named seats),
-- GENERAL_ADMISSION (ticket without a place) and PRIVATE_SESSION (a whole room / venue). Money is in integer tiyn (KZT), all instants are
-- timestamptz (the venue time zone, default Asia/Almaty, is only used to cut days). Nothing is seeded here: synthetic data comes only from
-- the guarded DEV seeder. Overselling is prevented by a row lock on the session plus partial unique indexes on seats and idempotency keys.

-- ---- permissions / flags ---------------------------------------------------------------------------------------------------
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS', 'LEISURE_OPERATIONS'));
ALTER TABLE identity.admin_role_permissions DROP CONSTRAINT admin_role_permissions_permission_check;
ALTER TABLE identity.admin_role_permissions ADD CONSTRAINT admin_role_permissions_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS', 'LEISURE_OPERATIONS'));
ALTER TABLE identity.admin_role_assignments DROP CONSTRAINT admin_role_assignments_product_code_check;
ALTER TABLE identity.admin_role_assignments ADD CONSTRAINT admin_role_assignments_product_code_check CHECK (product_code IN
    ('FOOD', 'GROCERY', 'FLOWERS', 'HOME_SERVICES', 'BEAUTY', 'RIDES', 'DELIVERY', 'AUTO', 'LEISURE'));
ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE'));
ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE'));

-- ---- catalog ----------------------------------------------------------------------------------------------------------------
CREATE TABLE marketplace.leisure_categories (
    code varchar(24) COLLATE "C" PRIMARY KEY CHECK (code ~ '^[A-Z_]+$'),
    name_ru varchar(80) NOT NULL,
    name_kk varchar(80) NOT NULL,
    name_en varchar(80) NOT NULL,
    default_booking_type varchar(20) COLLATE "C" NOT NULL
        CHECK (default_booking_type IN ('TIME_SLOT', 'CAPACITY', 'SEAT_MAP', 'GENERAL_ADMISSION', 'PRIVATE_SESSION')),
    family_friendly boolean NOT NULL DEFAULT false,
    needs_executor boolean NOT NULL DEFAULT false,
    enabled boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0
);
INSERT INTO marketplace.leisure_categories (code, name_ru, name_kk, name_en, default_booking_type, family_friendly, needs_executor, sort_order) VALUES
    ('CINEMA', 'Кинотеатры', 'Кинотеатрлар', 'Cinemas', 'SEAT_MAP', true, false, 1),
    ('BOWLING', 'Боулинг', 'Боулинг', 'Bowling', 'TIME_SLOT', true, false, 2),
    ('KARAOKE', 'Караоке', 'Караоке', 'Karaoke', 'PRIVATE_SESSION', false, false, 3),
    ('QUEST', 'Квест-комнаты', 'Квест бөлмелері', 'Escape rooms', 'TIME_SLOT', false, false, 4),
    ('KIDS_CENTER', 'Детские центры', 'Балалар орталықтары', 'Kids entertainment', 'CAPACITY', true, false, 5),
    ('TRAMPOLINE', 'Батутные парки', 'Батут парктері', 'Trampoline parks', 'CAPACITY', true, false, 6),
    ('GAMING_VR', 'Игровые и VR-клубы', 'Ойын және VR клубтары', 'Gaming and VR clubs', 'TIME_SLOT', false, false, 7),
    ('BILLIARDS', 'Бильярд', 'Бильярд', 'Billiards', 'TIME_SLOT', false, false, 8),
    ('CONCERT', 'Концерты', 'Концерттер', 'Concerts', 'SEAT_MAP', false, false, 9),
    ('THEATER', 'Театры', 'Театрлар', 'Theatres', 'SEAT_MAP', true, false, 10),
    ('EXHIBITION', 'Выставки', 'Көрмелер', 'Exhibitions', 'GENERAL_ADMISSION', true, false, 11),
    ('MASTERCLASS', 'Мастер-классы', 'Шеберлік сабақтары', 'Workshops', 'CAPACITY', true, true, 12),
    ('EXCURSION', 'Экскурсии', 'Экскурсиялар', 'Tours', 'CAPACITY', true, true, 13),
    ('ACTIVE', 'Активный отдых', 'Белсенді демалыс', 'Outdoor activities', 'CAPACITY', false, true, 14),
    ('FAMILY', 'Семейные развлечения', 'Отбасылық ойын-сауық', 'Family fun', 'GENERAL_ADMISSION', true, false, 15),
    ('OTHER', 'Другие мероприятия', 'Басқа іс-шаралар', 'Other events', 'GENERAL_ADMISSION', false, false, 16);

-- A venue (площадка) belongs to a partner (the organiser). It must be APPROVED by an administrator before it is visible.
CREATE TABLE marketplace.leisure_venues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    slug varchar(80) COLLATE "C" UNIQUE CHECK (slug ~ '^[a-z0-9-]{3,80}$'),
    name varchar(120) NOT NULL CHECK (length(btrim(name)) > 0),
    description varchar(2000) NOT NULL DEFAULT '',
    address varchar(200) NOT NULL DEFAULT '',
    district varchar(80) NOT NULL DEFAULT '',
    latitude double precision CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision CHECK (longitude BETWEEN -180 AND 180),
    photo_urls text[] NOT NULL DEFAULT '{}' CHECK (cardinality(photo_urls) <= 8),
    rules varchar(1500) NOT NULL DEFAULT '',
    cancellation_hours integer NOT NULL DEFAULT 2 CHECK (cancellation_hours BETWEEN 0 AND 720),
    timezone varchar(40) NOT NULL DEFAULT 'Asia/Almaty',
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED', 'BLOCKED')),
    moderation_note varchar(200),
    is_synthetic boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0
);
CREATE INDEX leisure_venues_partner_idx ON marketplace.leisure_venues (partner_id);
CREATE INDEX leisure_venues_status_idx ON marketplace.leisure_venues (status);

CREATE TABLE marketplace.leisure_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id uuid NOT NULL REFERENCES marketplace.leisure_venues(id),
    category_code varchar(24) COLLATE "C" NOT NULL REFERENCES marketplace.leisure_categories(code),
    booking_type varchar(20) COLLATE "C" NOT NULL
        CHECK (booking_type IN ('TIME_SLOT', 'CAPACITY', 'SEAT_MAP', 'GENERAL_ADMISSION', 'PRIVATE_SESSION')),
    title varchar(140) NOT NULL CHECK (length(btrim(title)) > 0),
    description varchar(2000) NOT NULL DEFAULT '',
    photo_urls text[] NOT NULL DEFAULT '{}' CHECK (cardinality(photo_urls) <= 8),
    duration_minutes integer NOT NULL DEFAULT 90 CHECK (duration_minutes BETWEEN 10 AND 1440),
    min_age integer NOT NULL DEFAULT 0 CHECK (min_age BETWEEN 0 AND 21),
    family_friendly boolean NOT NULL DEFAULT false,
    max_guests integer NOT NULL DEFAULT 10 CHECK (max_guests BETWEEN 1 AND 100),
    confirmation varchar(8) COLLATE "C" NOT NULL DEFAULT 'AUTO' CHECK (confirmation IN ('AUTO', 'MANUAL')),
    needs_executor boolean NOT NULL DEFAULT false,
    status varchar(12) COLLATE "C" NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PENDING', 'PUBLISHED', 'REJECTED', 'ARCHIVED', 'BLOCKED')),
    moderation_note varchar(200),
    is_synthetic boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0
);
CREATE INDEX leisure_events_venue_idx ON marketplace.leisure_events (venue_id);
CREATE INDEX leisure_events_category_idx ON marketplace.leisure_events (category_code, status);

-- pricing PER_TICKET: one ticket per person; PER_BOOKING: one price for the whole booking (a lane, a room), the ticket admits all guests.
CREATE TABLE marketplace.leisure_ticket_types (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES marketplace.leisure_events(id),
    name varchar(60) NOT NULL CHECK (length(btrim(name)) > 0),
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    pricing varchar(12) COLLATE "C" NOT NULL DEFAULT 'PER_TICKET' CHECK (pricing IN ('PER_TICKET', 'PER_BOOKING')),
    seat_zone varchar(24) COLLATE "C",
    active boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0,
    UNIQUE (event_id, name)
);

CREATE TABLE marketplace.leisure_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES marketplace.leisure_events(id),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    capacity integer NOT NULL CHECK (capacity BETWEEN 1 AND 5000),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED', 'CANCELLED')),
    cancel_reason varchar(200),
    created_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0,
    CHECK (ends_at > starts_at),
    UNIQUE (event_id, starts_at)
);
CREATE INDEX leisure_sessions_start_idx ON marketplace.leisure_sessions (starts_at) WHERE status = 'SCHEDULED';

-- Named seats of a SEAT_MAP session; the label is unique per session ("A1").
CREATE TABLE marketplace.leisure_seats (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES marketplace.leisure_sessions(id),
    row_label varchar(4) NOT NULL,
    seat_number integer NOT NULL CHECK (seat_number > 0),
    zone varchar(24) COLLATE "C" NOT NULL DEFAULT 'STANDARD',
    UNIQUE (session_id, row_label, seat_number)
);

-- ---- orders, holds, tickets ------------------------------------------------------------------------------------------------
-- A hold reserves units (and seats) for a few minutes. It is created from a server-priced selection; the client never sends prices.
CREATE TABLE transactions.leisure_holds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    session_id uuid NOT NULL REFERENCES marketplace.leisure_sessions(id),
    guests integer NOT NULL CHECK (guests BETWEEN 1 AND 100),
    total_minor bigint NOT NULL CHECK (total_minor >= 0),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CONSUMED', 'RELEASED', 'EXPIRED')),
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX leisure_holds_session_idx ON transactions.leisure_holds (session_id) WHERE status = 'ACTIVE';
CREATE INDEX leisure_holds_user_idx ON transactions.leisure_holds (user_id, created_at DESC);

CREATE TABLE transactions.leisure_hold_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hold_id uuid NOT NULL REFERENCES transactions.leisure_holds(id),
    ticket_type_id uuid NOT NULL REFERENCES marketplace.leisure_ticket_types(id),
    seat_id uuid REFERENCES marketplace.leisure_seats(id),
    unit_price_minor bigint NOT NULL CHECK (unit_price_minor >= 0)
);
CREATE INDEX leisure_hold_lines_hold_idx ON transactions.leisure_hold_lines (hold_id);
CREATE INDEX leisure_hold_lines_seat_idx ON transactions.leisure_hold_lines (seat_id) WHERE seat_id IS NOT NULL;

CREATE TABLE transactions.leisure_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    session_id uuid NOT NULL REFERENCES marketplace.leisure_sessions(id),
    event_id uuid NOT NULL REFERENCES marketplace.leisure_events(id),
    venue_id uuid NOT NULL REFERENCES marketplace.leisure_venues(id),
    guests integer NOT NULL CHECK (guests BETWEEN 1 AND 100),
    status varchar(10) COLLATE "C" NOT NULL CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED')),
    total_minor bigint NOT NULL CHECK (total_minor >= 0),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    payment_method varchar(12) COLLATE "C" NOT NULL CHECK (payment_method IN ('PAY_ON_SITE', 'TEST_CARD')),
    idempotency_key varchar(64) COLLATE "C" NOT NULL,
    hold_id uuid UNIQUE REFERENCES transactions.leisure_holds(id),
    cancelled_by varchar(10) COLLATE "C" CHECK (cancelled_by IN ('CUSTOMER', 'PARTNER', 'ADMIN', 'SYSTEM')),
    cancel_reason varchar(200),
    cancelled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0,
    UNIQUE (user_id, idempotency_key),
    CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL))
);
CREATE INDEX leisure_orders_user_idx ON transactions.leisure_orders (user_id, created_at DESC);
CREATE INDEX leisure_orders_session_idx ON transactions.leisure_orders (session_id);
CREATE INDEX leisure_orders_venue_idx ON transactions.leisure_orders (venue_id, created_at DESC);

-- A ticket. The QR code carries only "KT1.<id>.<nonce>": a random 128-bit secret checked by the server, no personal data.
CREATE TABLE transactions.leisure_tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES transactions.leisure_orders(id),
    session_id uuid NOT NULL REFERENCES marketplace.leisure_sessions(id),
    ticket_type_id uuid NOT NULL REFERENCES marketplace.leisure_ticket_types(id),
    seat_id uuid REFERENCES marketplace.leisure_seats(id),
    admits integer NOT NULL DEFAULT 1 CHECK (admits BETWEEN 1 AND 100),
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    nonce char(32) COLLATE "C" NOT NULL CHECK (nonce ~ '^[0-9a-f]{32}$'),
    status varchar(10) COLLATE "C" NOT NULL CHECK (status IN ('PENDING', 'VALID', 'USED', 'CANCELLED')),
    used_at timestamptz,
    used_by uuid REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((status = 'USED') = (used_at IS NOT NULL))
);
CREATE INDEX leisure_tickets_order_idx ON transactions.leisure_tickets (order_id);
CREATE INDEX leisure_tickets_session_idx ON transactions.leisure_tickets (session_id) WHERE status IN ('PENDING', 'VALID', 'USED');
-- A seat can belong to only one live ticket: the database refuses a second sale even if application locking were bypassed.
CREATE UNIQUE INDEX leisure_tickets_seat_uq ON transactions.leisure_tickets (session_id, seat_id)
    WHERE seat_id IS NOT NULL AND status IN ('PENDING', 'VALID', 'USED');

-- Append-only gate log: every scan, admitted or refused (a ticket-less row for unreadable codes).
CREATE TABLE transactions.leisure_checkins (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id uuid REFERENCES transactions.leisure_tickets(id),
    session_id uuid REFERENCES marketplace.leisure_sessions(id),
    venue_id uuid REFERENCES marketplace.leisure_venues(id),
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    result varchar(20) COLLATE "C" NOT NULL CHECK (result IN
        ('ADMITTED', 'DUPLICATE', 'INVALID', 'WRONG_ORGANIZATION', 'WRONG_SESSION', 'CANCELLED', 'NOT_CONFIRMED', 'EXPIRED', 'TOO_EARLY')),
    admits integer NOT NULL DEFAULT 0,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX leisure_checkins_session_idx ON transactions.leisure_checkins (session_id, occurred_at);
CREATE INDEX leisure_checkins_partner_idx ON transactions.leisure_checkins (partner_id, occurred_at DESC);
CREATE TRIGGER leisure_checkins_immutable BEFORE UPDATE OR DELETE ON transactions.leisure_checkins
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

CREATE TABLE transactions.leisure_order_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES transactions.leisure_orders(id),
    status varchar(12) COLLATE "C" NOT NULL,
    actor varchar(10) COLLATE "C" NOT NULL CHECK (actor IN ('CUSTOMER', 'PARTNER', 'ADMIN', 'SYSTEM')),
    actor_user_id uuid REFERENCES identity.users(id),
    reason varchar(200),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX leisure_order_events_order_idx ON transactions.leisure_order_events (order_id, id);
CREATE TRIGGER leisure_order_events_immutable BEFORE UPDATE OR DELETE ON transactions.leisure_order_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

-- ---- payments (DEV/TEST only, ledger entries, no provider, no card data) ---------------------------------------------------
CREATE TABLE transactions.leisure_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    order_id uuid NOT NULL UNIQUE REFERENCES transactions.leisure_orders(id),
    method varchar(12) COLLATE "C" NOT NULL CHECK (method IN ('PAY_ON_SITE', 'TEST_CARD')),
    status varchar(20) COLLATE "C" NOT NULL CHECK (status IN ('PAY_ON_SITE', 'TEST_HELD', 'TEST_CAPTURED', 'TEST_VOIDED', 'TEST_REFUNDED', 'TEST_PART_REFUNDED')),
    currency char(3) NOT NULL DEFAULT 'KZT' CHECK (currency = 'KZT'),
    held_minor bigint NOT NULL DEFAULT 0 CHECK (held_minor >= 0),
    captured_minor bigint NOT NULL DEFAULT 0 CHECK (captured_minor >= 0),
    refunded_minor bigint NOT NULL DEFAULT 0 CHECK (refunded_minor >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (refunded_minor <= captured_minor),
    CHECK (method = 'TEST_CARD' OR (held_minor = 0 AND captured_minor = 0 AND refunded_minor = 0 AND status = 'PAY_ON_SITE'))
);
CREATE INDEX leisure_payments_status_idx ON transactions.leisure_payments (status, updated_at DESC);

CREATE TABLE transactions.leisure_payment_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id uuid NOT NULL REFERENCES transactions.leisure_payments(id),
    kind varchar(12) COLLATE "C" NOT NULL CHECK (kind IN ('HOLD', 'CAPTURE', 'VOID', 'REFUND')),
    amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
    actor_type varchar(12) COLLATE "C" NOT NULL CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'ADMIN', 'SYSTEM')),
    actor_user_id uuid REFERENCES identity.users(id),
    reason varchar(200),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX leisure_payment_events_payment_idx ON transactions.leisure_payment_events (payment_id, id);
CREATE TRIGGER leisure_payment_events_immutable BEFORE UPDATE OR DELETE ON transactions.leisure_payment_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

-- ---- reviews, favourites, complaints ---------------------------------------------------------------------------------------
CREATE TABLE transactions.leisure_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL UNIQUE REFERENCES transactions.leisure_orders(id),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    event_id uuid NOT NULL REFERENCES marketplace.leisure_events(id),
    venue_id uuid NOT NULL REFERENCES marketplace.leisure_venues(id),
    rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body varchar(1000) NOT NULL DEFAULT '',
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'PUBLISHED' CHECK (status IN ('PUBLISHED', 'HIDDEN')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX leisure_reviews_event_idx ON transactions.leisure_reviews (event_id) WHERE status = 'PUBLISHED';

CREATE TABLE transactions.leisure_favorites (
    user_id uuid NOT NULL REFERENCES identity.users(id),
    event_id uuid NOT NULL REFERENCES marketplace.leisure_events(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, event_id)
);

CREATE TABLE transactions.leisure_complaints (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    venue_id uuid NOT NULL REFERENCES marketplace.leisure_venues(id),
    order_id uuid REFERENCES transactions.leisure_orders(id),
    body varchar(1000) NOT NULL CHECK (length(btrim(body)) > 0),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED')),
    resolution varchar(300),
    resolved_by uuid REFERENCES identity.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz
);
CREATE INDEX leisure_complaints_status_idx ON transactions.leisure_complaints (status, created_at DESC);

-- ---- executors (guide, host, instructor, animator): only for events that need one ---------------------------------------------
CREATE TABLE transactions.leisure_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES marketplace.leisure_sessions(id),
    executor_user_id uuid NOT NULL REFERENCES identity.users(id),
    role varchar(12) COLLATE "C" NOT NULL CHECK (role IN ('GUIDE', 'HOST', 'INSTRUCTOR', 'ANIMATOR', 'ORGANIZER')),
    status varchar(10) COLLATE "C" NOT NULL DEFAULT 'OFFERED' CHECK (status IN ('OFFERED', 'ACCEPTED', 'DECLINED', 'STARTED', 'COMPLETED', 'CANCELLED')),
    assigned_by uuid NOT NULL REFERENCES identity.users(id),
    note varchar(200),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX leisure_assignments_live_uq ON transactions.leisure_assignments (session_id, executor_user_id) WHERE status IN ('OFFERED', 'ACCEPTED', 'STARTED');
CREATE INDEX leisure_assignments_executor_idx ON transactions.leisure_assignments (executor_user_id, created_at DESC);

-- ---- audit -----------------------------------------------------------------------------------------------------------------
-- Append-only record of partner and administrator actions on Leisure (moderation, price changes, refunds, blocks, switches).
CREATE TABLE marketplace.leisure_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    actor_type varchar(10) COLLATE "C" NOT NULL CHECK (actor_type IN ('PARTNER', 'ADMIN', 'EXECUTOR')),
    partner_id uuid REFERENCES marketplace.partners(id),
    action varchar(40) NOT NULL,
    target varchar(80) NOT NULL,
    detail varchar(300),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX leisure_audit_partner_idx ON marketplace.leisure_audit (partner_id, id DESC);
CREATE INDEX leisure_audit_time_idx ON marketplace.leisure_audit (id DESC);
CREATE TRIGGER leisure_audit_immutable BEFORE UPDATE OR DELETE ON marketplace.leisure_audit
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
