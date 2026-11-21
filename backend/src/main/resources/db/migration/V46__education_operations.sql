ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS',
     'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS', 'FOOD_OPERATIONS', 'EDUCATION_OPERATIONS'));

ALTER TABLE marketplace.education_cohorts ADD COLUMN instructor_id uuid REFERENCES identity.users(id);
CREATE INDEX education_cohorts_instructor_idx ON marketplace.education_cohorts(instructor_id, starts_at, id);

CREATE TABLE marketplace.education_course_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id uuid NOT NULL REFERENCES marketplace.education_courses(id),
    actor_user_id uuid NOT NULL REFERENCES identity.users(id),
    action varchar(24) NOT NULL,
    reason varchar(200),
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX education_course_events_idx ON marketplace.education_course_events(course_id, id DESC);
CREATE TRIGGER education_course_events_immutable BEFORE UPDATE OR DELETE ON marketplace.education_course_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();

ALTER TABLE transactions.education_enrollments ADD COLUMN attendance varchar(12)
    CHECK (attendance IN ('PRESENT', 'ABSENT'));
