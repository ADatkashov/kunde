CREATE TABLE marketplace.education_course_quizzes (
    course_id uuid PRIMARY KEY REFERENCES marketplace.education_courses(id),
    question varchar(300) NOT NULL,
    choices text[] NOT NULL CHECK (cardinality(choices) BETWEEN 2 AND 6),
    correct_choice integer NOT NULL CHECK (correct_choice >= 0 AND correct_choice < cardinality(choices)),
    max_attempts integer NOT NULL CHECK (max_attempts BETWEEN 1 AND 10)
);

CREATE TABLE transactions.education_quiz_attempts (
    enrollment_id uuid NOT NULL,
    course_id uuid NOT NULL,
    request_id uuid NOT NULL,
    selected_choice integer NOT NULL CHECK (selected_choice >= 0 AND selected_choice < 6),
    passed boolean NOT NULL,
    attempted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (enrollment_id, request_id),
    FOREIGN KEY (enrollment_id, course_id) REFERENCES transactions.education_enrollments(id, course_id),
    FOREIGN KEY (course_id) REFERENCES marketplace.education_course_quizzes(course_id)
);

CREATE TRIGGER education_quiz_attempts_immutable BEFORE UPDATE OR DELETE ON transactions.education_quiz_attempts
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
