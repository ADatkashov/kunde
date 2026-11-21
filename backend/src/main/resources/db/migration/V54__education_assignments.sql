CREATE TABLE marketplace.education_assignments (
    course_id uuid PRIMARY KEY REFERENCES marketplace.education_courses(id),
    prompt varchar(1500) NOT NULL CHECK (length(btrim(prompt)) > 0)
);

CREATE TABLE transactions.education_assignment_submissions (
    enrollment_id uuid PRIMARY KEY,
    course_id uuid NOT NULL REFERENCES marketplace.education_assignments(course_id),
    response varchar(5000) NOT NULL CHECK (length(btrim(response)) > 0),
    status varchar(12) NOT NULL CHECK (status IN ('SUBMITTED','APPROVED','RETURNED')),
    feedback varchar(1000),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    FOREIGN KEY (enrollment_id, course_id) REFERENCES transactions.education_enrollments(id, course_id)
);
