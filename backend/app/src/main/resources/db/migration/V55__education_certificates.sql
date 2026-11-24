CREATE TABLE transactions.education_certificates (
    enrollment_id uuid PRIMARY KEY REFERENCES transactions.education_enrollments(id),
    code uuid NOT NULL UNIQUE,
    course_title varchar(180) NOT NULL,
    organization_name varchar(120) NOT NULL,
    learner_name varchar(80),
    completed_at timestamptz NOT NULL,
    revoked_at timestamptz,
    revoked_by uuid REFERENCES identity.users(id),
    revocation_reason varchar(200),
    CHECK ((revoked_at IS NULL AND revoked_by IS NULL AND revocation_reason IS NULL) OR
           (revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND revocation_reason IS NOT NULL))
);

-- Old and new instances may overlap during a rolling deployment. The snapshot must
-- be written wherever the completion is first committed, including by an older instance.
CREATE FUNCTION transactions.snapshot_education_certificate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO transactions.education_certificates
        (enrollment_id,code,course_title,organization_name,learner_name,completed_at)
    SELECT NEW.id,NEW.certificate_code,c.title,p.display_name,cp.display_name,NEW.completed_at
    FROM marketplace.education_courses c
    JOIN marketplace.partners p ON p.id=c.partner_id
    LEFT JOIN profile.consumer_profiles cp ON cp.user_id=NEW.user_id
    WHERE c.id=NEW.course_id
    ON CONFLICT (enrollment_id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE TRIGGER education_certificate_snapshot
    AFTER UPDATE OF certificate_code ON transactions.education_enrollments
    FOR EACH ROW WHEN (OLD.certificate_code IS NULL AND NEW.certificate_code IS NOT NULL)
    EXECUTE FUNCTION transactions.snapshot_education_certificate();

INSERT INTO transactions.education_certificates(enrollment_id,code,course_title,organization_name,learner_name,completed_at)
SELECT e.id,e.certificate_code,c.title,p.display_name,cp.display_name,e.completed_at
FROM transactions.education_enrollments e
JOIN marketplace.education_courses c ON c.id=e.course_id
JOIN marketplace.partners p ON p.id=c.partner_id
LEFT JOIN profile.consumer_profiles cp ON cp.user_id=e.user_id
WHERE e.certificate_code IS NOT NULL
ON CONFLICT (enrollment_id) DO NOTHING;
