package kz.kunde.education;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EducationEnrollmentService {
    private static final String HISTORY = """
            select e.id, e.cohort_id, e.course_id, c.title, h.format, h.starts_at, h.ends_at,
                e.amount_minor, case when e.completed_at is null then 'CONFIRMED' else 'COMPLETED' end as status,
                p.status as payment_status, e.completed_at, e.certificate_code,
                case when x.code is null then null when x.revoked_at is null then 'VALID' else 'REVOKED' end as certificate_status
            from transactions.education_enrollments e
            join transactions.education_payment_events p on p.enrollment_id=e.id
            join marketplace.education_courses c on c.id=e.course_id
            join marketplace.education_cohorts h on h.id=e.cohort_id
            left join transactions.education_certificates x on x.enrollment_id=e.id
            where e.user_id=:user
            """;

    private final JdbcClient db;
    private final FeatureToggles toggles;
    private final PartnerDirectory partnerDirectory;

    public EducationEnrollmentService(JdbcClient db, FeatureToggles toggles, PartnerDirectory partnerDirectory) {
        this.db = db;
        this.toggles = toggles;
        this.partnerDirectory = partnerDirectory;
    }

    public List<Cohort> cohorts(UUID course) {
        requireIntake();
        return db.sql("""
                select h.id, h.format, h.starts_at, h.ends_at, f.price_minor,
                       greatest(0, h.capacity - (select count(*) from transactions.education_enrollments e
                                                 where e.cohort_id=h.id))::integer as remaining
                from marketplace.education_cohorts h
                join marketplace.education_course_formats f on f.course_id=h.course_id and f.format=h.format
                join marketplace.education_courses c on c.id=h.course_id
                join marketplace.partners p on p.id=c.partner_id
                where h.course_id=:course and h.open and (h.starts_at is null or h.starts_at > now())
                  and c.status='PUBLISHED' and c.synthetic and p.verification_status='APPROVED'
                order by h.starts_at nulls first, h.id
                limit 100
                """).param("course", course).query(Cohort.class).list();
    }

    @Transactional
    public Placed enroll(UUID user, UUID cohort, long amount, String key) {
        // Serialize a customer's requests across cohorts before locking the selected cohort.
        db.sql("select id from identity.users where id=:user for update").param("user", user).query(UUID.class).single();
        var replay = db.sql(HISTORY + " and e.request_key=:key").param("user", user).param("key", key)
                .query(Enrollment.class).optional();
        if (replay.isPresent()) {
            var previous = replay.get();
            if (!previous.cohortId().equals(cohort) || previous.amountMinor() != amount) {
                throw conflict("IDEMPOTENCY_CONFLICT", "The key already belongs to a different request");
            }
            return new Placed(previous, false);
        }
        requireIntake();
        var group = db.sql("""
                select h.course_id, h.capacity, f.price_minor, h.starts_at
                from marketplace.education_cohorts h
                join marketplace.education_course_formats f on f.course_id=h.course_id and f.format=h.format
                join marketplace.education_courses c on c.id=h.course_id
                join marketplace.partners p on p.id=c.partner_id
                where h.id=:id and h.open and (h.starts_at is null or h.starts_at > clock_timestamp())
                  and c.status='PUBLISHED' and c.synthetic and p.verification_status='APPROVED'
                for update of h for share of c, p, f
                """).param("id", cohort).query(Group.class).optional()
                .orElseThrow(() -> conflict("COHORT_UNAVAILABLE", "This cohort is unavailable"));
        if (group.startsAt() != null && !group.startsAt().isAfter(OffsetDateTime.now())) {
            throw conflict("COHORT_UNAVAILABLE", "This cohort has already started");
        }
        if (group.priceMinor() != amount) {
            throw conflict("PRICE_CHANGED", "The price changed. Reload the course before enrolling");
        }
        if (db.sql("select exists(select 1 from transactions.education_enrollments where user_id=:user and course_id=:course)")
                .param("user", user).param("course", group.courseId()).query(Boolean.class).single()) {
            throw conflict("ALREADY_ENROLLED", "You are already enrolled in this course");
        }
        long occupied = db.sql("select count(*) from transactions.education_enrollments where cohort_id=:id")
                .param("id", cohort).query(Long.class).single();
        if (occupied >= group.capacity()) {
            throw conflict("COHORT_FULL", "This cohort is full");
        }
        UUID id = UUID.randomUUID();
        db.sql("""
                insert into transactions.education_enrollments(id,user_id,course_id,cohort_id,request_key,amount_minor)
                values (:id,:user,:course,:cohort,:key,:amount)
                """).param("id", id).param("user", user).param("course", group.courseId())
                .param("cohort", cohort).param("key", key).param("amount", group.priceMinor()).update();
        db.sql("insert into transactions.education_payment_events(enrollment_id,method,status) values (:id,'TEST_CARD','TEST_CAPTURED')")
                .param("id", id).update();
        return new Placed(owned(user, id), true);
    }

    public List<Enrollment> history(UUID user, int limit, int offset) {
        return db.sql(HISTORY + " order by e.created_at desc, e.id limit :limit offset :offset")
                .param("user", user).param("limit", limit).param("offset", offset).query(Enrollment.class).list();
    }

    public Learning learning(UUID user, UUID id) {
        var enrollment = owned(user, id);
        return new Learning(enrollment, lessons(enrollment), quiz(enrollment), assignment(enrollment));
    }

    @Transactional
    public Learning completeLesson(UUID user, UUID id, int module, int lesson) {
        var enrollment = lockEnrollment(user, id);
        var lessons = lessons(enrollment);
        var selected = lessons.stream().filter(item -> item.modulePosition() == module && item.lessonPosition() == lesson)
                .findFirst().orElseThrow(EducationEnrollmentService::notFound);
        if (!selected.completed()) {
            if (!lessons.stream().filter(item -> !item.completed()).findFirst().orElseThrow().equals(selected)) {
                throw conflict("LESSON_LOCKED", "Complete the previous lesson first");
            }
            db.sql("""
                    insert into transactions.education_lesson_progress(enrollment_id,course_id,module_position,lesson_position)
                    values (:id,:course,:module,:lesson)
                    """).param("id", id).param("course", enrollment.courseId()).param("module", module)
                    .param("lesson", lesson).update();
        }
        completeCourseIfEligible(enrollment);
        return learning(user, id);
    }

    @Transactional
    public Learning attemptQuiz(UUID user, UUID id, UUID requestId, int choice) {
        var enrollment = lockEnrollment(user, id);
        var quiz = quiz(enrollment);
        if (quiz == null) throw notFound();
        var previous = db.sql("""
                select selected_choice from transactions.education_quiz_attempts
                where enrollment_id=:id and request_id=:request
                """).param("id", id).param("request", requestId).query(Integer.class).optional();
        if (previous.isPresent()) {
            if (previous.get() != choice) throw conflict("IDEMPOTENCY_CONFLICT", "This request ID already has a different answer");
            return learning(user, id);
        }
        if (!lessons(enrollment).stream().allMatch(Lesson::completed)) {
            throw conflict("QUIZ_LOCKED", "Complete the text lessons first");
        }
        if (quiz.passed() || quiz.remainingAttempts() == 0 || enrollment.completedAt() != null) {
            throw conflict("QUIZ_CLOSED", "This quiz no longer accepts attempts");
        }
        if (choice < 0 || choice >= quiz.choices().size()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CHOICE", "Choose one answer from the list");
        }
        db.sql("""
                insert into transactions.education_quiz_attempts(enrollment_id,course_id,request_id,selected_choice,passed)
                select :id,:course,:request,:choice,correct_choice=:choice
                from marketplace.education_course_quizzes where course_id=:course
                """).param("id", id).param("course", enrollment.courseId()).param("request", requestId).param("choice", choice)
                .update();
        completeCourseIfEligible(enrollment);
        return learning(user, id);
    }

    @Transactional
    public Learning submitAssignment(UUID user, UUID id, String response) {
        var enrollment = lockEnrollment(user, id);
        var assignment = assignment(enrollment);
        if (assignment == null) throw notFound();
        if (!lessons(enrollment).stream().allMatch(Lesson::completed)) {
            throw conflict("ASSIGNMENT_LOCKED", "Complete the text lessons first");
        }
        if (enrollment.completedAt() != null) throw conflict("ASSIGNMENT_CLOSED", "The course is completed");
        if ("SUBMITTED".equals(assignment.status()) && response.equals(assignment.response())) return learning(user, id);
        int changed = db.sql("""
                insert into transactions.education_assignment_submissions(enrollment_id,course_id,response,status)
                values (:id,:course,:response,'SUBMITTED')
                on conflict (enrollment_id) do update set response=excluded.response,status='SUBMITTED',
                    feedback=null,submitted_at=now(),reviewed_at=null
                where transactions.education_assignment_submissions.status='RETURNED'
                """).param("id", id).param("course", enrollment.courseId()).param("response", response).update();
        if (changed == 0) throw conflict("ASSIGNMENT_CLOSED", "Wait for the instructor to review your submission");
        return learning(user, id);
    }

    @Transactional
    public Assignment reviewAssignment(UUID instructor, UUID cohort, UUID id, boolean approved, String feedback) {
        UUID[] row = db.sql("""
                select e.user_id, c.partner_id from transactions.education_enrollments e
                join marketplace.education_cohorts h on h.id=e.cohort_id and h.instructor_id=:actor
                join marketplace.education_courses c on c.id=e.course_id and c.status='PUBLISHED'
                where e.cohort_id=:cohort and e.id=:id for update of e for share of h,c
                """).param("actor", instructor).param("cohort", cohort).param("id", id)
                .query((rs, n) -> new UUID[] {rs.getObject(1, UUID.class), rs.getObject(2, UUID.class)}).optional()
                .orElseThrow(EducationEnrollmentService::notFound);
        // Shared lock on the partner and staff rows until commit, as the former join did (ADR-021).
        if (!partnerDirectory.lockActiveStaffOfApprovedPartner(instructor, row[1])) throw notFound();
        UUID user = row[0];
        var enrollment = owned(user, id);
        var assignment = assignment(enrollment);
        if (assignment == null || assignment.response() == null) throw notFound();
        String next = approved ? "APPROVED" : "RETURNED";
        if (next.equals(assignment.status()) && feedback.equals(assignment.feedback())) return assignment;
        int changed = db.sql("""
                update transactions.education_assignment_submissions set status=:status,feedback=:feedback,reviewed_at=now()
                where enrollment_id=:id and status='SUBMITTED'
                """).param("id", id).param("status", next).param("feedback", feedback).update();
        if (changed == 0) throw conflict("ASSIGNMENT_CLOSED", "The submission has already been reviewed");
        db.sql("""
                insert into marketplace.education_course_events(course_id,actor_user_id,action,reason)
                values (:course,:actor,:action,:id)
                """).param("course", enrollment.courseId()).param("actor", instructor)
                .param("action", "ASSIGNMENT_" + next).param("id", id.toString()).update();
        completeCourseIfEligible(enrollment);
        return assignment(enrollment);
    }

    private Assignment assignment(Enrollment enrollment) {
        return db.sql("""
                select a.prompt,s.response,s.status,s.feedback from marketplace.education_assignments a
                left join transactions.education_assignment_submissions s
                  on s.course_id=a.course_id and s.enrollment_id=:id
                where a.course_id=:course
                """).param("id", enrollment.id()).param("course", enrollment.courseId())
                .query(Assignment.class).optional().orElse(null);
    }

    private Enrollment lockEnrollment(UUID user, UUID id) {
        db.sql("select id from transactions.education_enrollments where user_id=:user and id=:id for update")
                .param("user", user).param("id", id).query(UUID.class).optional()
                .orElseThrow(EducationEnrollmentService::notFound);
        return owned(user, id);
    }

    private void completeCourseIfEligible(Enrollment enrollment) {
        if (enrollment.completedAt() != null) return;
        var lessons = lessons(enrollment);
        if (lessons.isEmpty() || !lessons.stream().allMatch(Lesson::completed)) return;
        var quiz = quiz(enrollment);
        var assignment = assignment(enrollment);
        if ((quiz == null || quiz.passed()) && (assignment == null || "APPROVED".equals(assignment.status()))) {
            db.sql("update transactions.education_enrollments set completed_at=now(), certificate_code=:code where id=:id")
                    .param("id", enrollment.id()).param("code", UUID.randomUUID()).update();
        }
    }

    private Quiz quiz(Enrollment enrollment) {
        if (!"ONLINE_RECORDED".equals(enrollment.format())) return null;
        return db.sql("""
                select q.question,q.choices,q.max_attempts-count(a.request_id) as remaining,
                       coalesce(bool_or(a.passed),false) as passed
                from marketplace.education_course_quizzes q
                left join transactions.education_quiz_attempts a on a.enrollment_id=:id and a.course_id=q.course_id
                where q.course_id=:course group by q.course_id
                """).param("id", enrollment.id()).param("course", enrollment.courseId())
                .query((rs, row) -> new Quiz(rs.getString("question"), List.of((String[]) rs.getArray("choices").getArray()),
                        rs.getInt("remaining"), rs.getBoolean("passed"))).optional().orElse(null);
    }

    private Enrollment owned(UUID user, UUID id) {
        return db.sql(HISTORY + " and e.id=:id").param("user", user).param("id", id)
                .query(Enrollment.class).optional().orElseThrow(EducationEnrollmentService::notFound);
    }

    private List<Lesson> lessons(Enrollment enrollment) {
        if (!"ONLINE_RECORDED".equals(enrollment.format())) {
            return List.of();
        }
        var rows = db.sql("""
                select l.module_position, l.position as lesson_position, l.title, l.recorded_text as content,
                       (p.enrollment_id is not null) as completed
                from marketplace.education_course_lessons l
                left join transactions.education_lesson_progress p on p.enrollment_id=:id
                     and p.module_position=l.module_position and p.lesson_position=l.position
                where l.course_id=:course and l.recorded_text is not null
                order by l.module_position, l.position
                """).param("id", enrollment.id()).param("course", enrollment.courseId()).query(Lesson.class).list();
        boolean locked = false;
        var result = new java.util.ArrayList<Lesson>();
        for (var row : rows) {
            result.add(locked && !row.completed()
                    ? new Lesson(row.modulePosition(), row.lessonPosition(), row.title(), null, false) : row);
            locked |= !row.completed();
        }
        return result;
    }

    private void requireIntake() {
        if (!toggles.enabled(FeatureToggles.Feature.EDUCATION)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "EDUCATION_UNAVAILABLE", "Education is unavailable");
        }
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "EDUCATION_RESOURCE_NOT_FOUND", "Resource not found");
    }

    private static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    private record Group(UUID courseId, int capacity, long priceMinor, OffsetDateTime startsAt) {}
    public record Cohort(UUID id, String format, OffsetDateTime startsAt, OffsetDateTime endsAt, long priceMinor, int remaining) {}
    public record Enrollment(UUID id, UUID cohortId, UUID courseId, String title, String format, OffsetDateTime startsAt,
            OffsetDateTime endsAt, long amountMinor, String status, String paymentStatus, OffsetDateTime completedAt, UUID certificateCode, String certificateStatus) {}
    public record Lesson(int modulePosition, int lessonPosition, String title, String content, boolean completed) {}
    public record Learning(Enrollment enrollment, List<Lesson> lessons, Quiz quiz, Assignment assignment) {}
    public record Assignment(String prompt, String response, String status, String feedback) {}
    public record Quiz(String question, List<String> choices, int remainingAttempts, boolean passed) {}
    public record Placed(Enrollment enrollment, boolean created) {}
}
