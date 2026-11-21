ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION'));
ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION'));

CREATE TABLE marketplace.education_courses (
    id uuid PRIMARY KEY,
    partner_id uuid NOT NULL REFERENCES marketplace.partners(id),
    category varchar(48) NOT NULL,
    title varchar(180) NOT NULL,
    description text NOT NULL,
    city varchar(100) NOT NULL,
    language varchar(8) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'PENDING_REVIEW', 'PUBLISHED', 'REJECTED', 'SUSPENDED', 'ARCHIVED')),
    synthetic boolean NOT NULL DEFAULT false
);

CREATE INDEX education_published_courses ON marketplace.education_courses (city, category, title, id)
    WHERE status = 'PUBLISHED';

CREATE TABLE marketplace.education_course_formats (
    course_id uuid NOT NULL REFERENCES marketplace.education_courses(id),
    format varchar(20) NOT NULL
        CHECK (format IN ('ONLINE_RECORDED', 'ONLINE_LIVE', 'OFFLINE_GROUP', 'OFFLINE_INDIVIDUAL', 'HYBRID')),
    price_minor bigint NOT NULL CHECK (price_minor >= 0),
    duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
    PRIMARY KEY (course_id, format)
);

CREATE TABLE marketplace.education_course_modules (
    course_id uuid NOT NULL REFERENCES marketplace.education_courses(id),
    position integer NOT NULL CHECK (position > 0),
    title varchar(180) NOT NULL,
    PRIMARY KEY (course_id, position)
);

CREATE TABLE marketplace.education_course_lessons (
    course_id uuid NOT NULL,
    module_position integer NOT NULL,
    position integer NOT NULL CHECK (position > 0),
    title varchar(180) NOT NULL,
    duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
    PRIMARY KEY (course_id, module_position, position),
    FOREIGN KEY (course_id, module_position) REFERENCES marketplace.education_course_modules(course_id, position)
);
