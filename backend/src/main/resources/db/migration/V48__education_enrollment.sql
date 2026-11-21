CREATE TABLE marketplace.education_cohorts (
    id uuid PRIMARY KEY,
    course_id uuid NOT NULL,
    format varchar(20) NOT NULL,
    starts_at timestamptz,
    ends_at timestamptz,
    capacity integer NOT NULL CHECK (capacity > 0),
    open boolean NOT NULL DEFAULT false,
    CHECK ((starts_at IS NULL AND ends_at IS NULL AND format = 'ONLINE_RECORDED') OR
           (starts_at IS NOT NULL AND ends_at IS NOT NULL AND starts_at < ends_at)),
    UNIQUE (id, course_id),
    FOREIGN KEY (course_id, format) REFERENCES marketplace.education_course_formats(course_id, format)
);

CREATE INDEX education_cohorts_course_idx ON marketplace.education_cohorts(course_id, starts_at, id);

CREATE TABLE transactions.education_enrollments (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES identity.users(id),
    course_id uuid NOT NULL,
    cohort_id uuid NOT NULL,
    request_key varchar(80) NOT NULL,
    amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    certificate_code uuid UNIQUE,
    CHECK ((completed_at IS NULL) = (certificate_code IS NULL)),
    UNIQUE (user_id, request_key),
    UNIQUE (user_id, course_id),
    UNIQUE (id, course_id),
    FOREIGN KEY (cohort_id, course_id) REFERENCES marketplace.education_cohorts(id, course_id)
);

CREATE INDEX education_enrollments_capacity_idx ON transactions.education_enrollments(cohort_id);
CREATE INDEX education_enrollments_user_idx ON transactions.education_enrollments(user_id, created_at DESC, id);

CREATE TABLE transactions.education_payment_events (
    enrollment_id uuid PRIMARY KEY REFERENCES transactions.education_enrollments(id),
    method varchar(16) NOT NULL CHECK (method = 'TEST_CARD'),
    status varchar(20) NOT NULL CHECK (status = 'TEST_CAPTURED'),
    captured_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE marketplace.education_course_lessons ADD COLUMN recorded_text text;

CREATE TABLE transactions.education_lesson_progress (
    enrollment_id uuid NOT NULL,
    course_id uuid NOT NULL,
    module_position integer NOT NULL,
    lesson_position integer NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (enrollment_id, module_position, lesson_position),
    FOREIGN KEY (enrollment_id, course_id) REFERENCES transactions.education_enrollments(id, course_id),
    FOREIGN KEY (course_id, module_position, lesson_position)
        REFERENCES marketplace.education_course_lessons(course_id, module_position, position)
);

CREATE TRIGGER education_payment_events_immutable BEFORE UPDATE OR DELETE ON transactions.education_payment_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
