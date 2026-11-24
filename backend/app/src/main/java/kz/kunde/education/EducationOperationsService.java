package kz.kunde.education;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.authz.AdminGrants;
import kz.kunde.partner.PartnerService;
import kz.kunde.partner.PartnerService.Role;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.partner.PartnerDirectory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.SqlArrayValue;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EducationOperationsService {
    private static final String COURSES = """
            select c.id, c.partner_id, c.title, c.description, c.status, p.display_name as organization,
                (select min(f.format) from marketplace.education_course_formats f where f.course_id=c.id) as format
            from marketplace.education_courses c join marketplace.partners p on p.id=c.partner_id
            """;
    private static final String SESSIONS = """
            select h.id, h.course_id, c.title, h.format, h.starts_at, h.ends_at, h.capacity, h.instructor_id
            from marketplace.education_cohorts h join marketplace.education_courses c on c.id=h.course_id
            """;
    private final JdbcClient db;
    private final PartnerService partners;
    private final AdminGrants admins;
    private final FeatureToggles toggles;
    private final PartnerDirectory partnerDirectory;

    public EducationOperationsService(JdbcClient db, PartnerService partners, AdminGrants admins, FeatureToggles toggles,
            PartnerDirectory partnerDirectory) {
        this.db = db;
        this.partnerDirectory = partnerDirectory;
        this.partners = partners;
        this.admins = admins;
        this.toggles = toggles;
    }

    public List<Course> partnerCourses(UUID actor, UUID partner) {
        partners.requireProcessing(actor, partner);
        return db.sql(COURSES + " where c.partner_id=:partner order by c.title,c.id limit 100")
                .param("partner", partner).query(Course.class).list();
    }

    public List<Instructor> instructors(UUID actor, UUID partner) {
        partners.requireProcessing(actor, partner, Role.OWNER, Role.MANAGER);
        return db.sql("""
                select s.user_id as id, coalesce(p.display_name, left(s.user_id::text,8)) as name
                from marketplace.partner_staff s
                join identity.users u on u.id=s.user_id and u.status='ACTIVE'
                left join profile.consumer_profiles p on p.user_id=s.user_id
                where s.partner_id=:partner and s.status='ACTIVE'
                order by name,s.user_id limit 100
                """).param("partner", partner).query(Instructor.class).list();
    }

    @Transactional
    public Course create(UUID actor, UUID partner, Draft input) {
        manage(actor, partner);
        UUID id = UUID.randomUUID();
        db.sql("""
                insert into marketplace.education_courses(id,partner_id,category,title,description,city,language,synthetic)
                values (:id,:partner,:category,:title,:description,:city,:language,true)
                """).param("id", id).param("partner", partner).param("category", input.category().strip())
                .param("title", input.title().strip()).param("description", input.description().strip())
                .param("city", input.city().strip()).param("language", input.language().strip()).update();
        db.sql("""
                insert into marketplace.education_course_formats(course_id,format,price_minor,duration_minutes)
                values (:id,:format,:price,:duration)
                """).param("id", id).param("format", input.format().name()).param("price", input.priceMinor())
                .param("duration", input.durationMinutes()).update();
        if (input.format() == EducationCatalogController.Format.ONLINE_RECORDED) {
            if (input.recordedText() == null || input.recordedText().isBlank()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "LESSON_REQUIRED", "A recorded course needs a text lesson");
            }
            db.sql("insert into marketplace.education_course_modules values (:id,1,:title)")
                    .param("id", id).param("title", input.title().strip()).update();
            db.sql("""
                    insert into marketplace.education_course_lessons
                        (course_id,module_position,position,title,duration_minutes,recorded_text)
                    values (:id,1,1,:title,:duration,:content)
                    """).param("id", id).param("title", input.title().strip()).param("duration", input.durationMinutes())
                    .param("content", input.recordedText().strip()).update();
        }
        if (input.assignmentPrompt() != null && !input.assignmentPrompt().isBlank()) {
            if (input.format() != EducationCatalogController.Format.ONLINE_RECORDED) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ASSIGNMENT_REQUIRES_RECORDED_FORMAT", "Choose recorded training");
            }
            db.sql("insert into marketplace.education_assignments(course_id,prompt) values (:id,:prompt)")
                    .param("id", id).param("prompt", input.assignmentPrompt().strip()).update();
        }
        if (input.quiz() != null) {
            addQuiz(id, input.format(), input.quiz());
        }
        event(id, actor, "DRAFT_CREATED", null);
        return course(id);
    }

    private void addQuiz(UUID course, EducationCatalogController.Format format, QuizInput quiz) {
        if (format != EducationCatalogController.Format.ONLINE_RECORDED) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "QUIZ_REQUIRES_RECORDED_FORMAT", "Choose recorded training");
        }
        var choices = quiz.choices().stream().map(String::strip).toList();
        if (quiz.correctChoice() >= choices.size() || choices.stream().distinct().count() != choices.size()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QUIZ_CHOICES", "Choose distinct answers and a valid correct answer");
        }
        db.sql("""
                insert into marketplace.education_course_quizzes(course_id,question,choices,correct_choice,max_attempts)
                values (:course,:question,:choices,:correct,:attempts)
                """).param("course", course).param("question", quiz.question().strip())
                .param("choices", new SqlArrayValue("text", choices.toArray())).param("correct", quiz.correctChoice())
                .param("attempts", quiz.maxAttempts()).update();
    }

    @Transactional
    public Course submit(UUID actor, UUID partner, UUID id) {
        manage(actor, partner);
        ownCourse(partner, id);
        transition(id, "PENDING_REVIEW", "DRAFT", "REJECTED");
        event(id, actor, "SUBMITTED", null);
        return course(id);
    }

    @Transactional
    public Session createSession(UUID actor, UUID partner, UUID id, CohortInput input) {
        manage(actor, partner);
        ownCourse(partner, id);
        if (input.instructorId() != null) {
            partners.requireProcessing(input.instructorId(), partner);
        }
        boolean recorded = input.format() == EducationCatalogController.Format.ONLINE_RECORDED;
        if ((input.startsAt() == null || input.endsAt() == null)
                ? !recorded || input.startsAt() != null || input.endsAt() != null
                : !input.startsAt().isAfter(OffsetDateTime.now()) || !input.endsAt().isAfter(input.startsAt())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_SCHEDULE", "Choose a valid future schedule");
        }
        if (input.instructorId() == null && db.sql("select exists(select 1 from marketplace.education_assignments where course_id=:id)")
                .param("id", id).query(Boolean.class).single()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INSTRUCTOR_REQUIRED", "Choose an instructor to review assignments");
        }
        UUID session = UUID.randomUUID();
        int inserted = db.sql("""
                insert into marketplace.education_cohorts(id,course_id,format,starts_at,ends_at,capacity,open,instructor_id)
                select :session,c.id,f.format,:starts,:ends,:capacity,true,:instructor
                from marketplace.education_courses c
                join marketplace.education_course_formats f on f.course_id=c.id and f.format=:format
                where c.id=:course and c.status in ('DRAFT','PENDING_REVIEW','PUBLISHED')
                """).param("session", session).param("course", id).param("format", input.format().name())
                .param("starts", input.startsAt()).param("ends", input.endsAt())
                .param("capacity", input.capacity()).param("instructor", input.instructorId()).update();
        if (inserted == 0) {
            throw conflict("COHORT_UNAVAILABLE", "Course or format is unavailable for scheduling");
        }
        event(id, actor, "COHORT_CREATED", session.toString());
        return db.sql(SESSIONS + " where h.id=:session").param("session", session).query(Session.class).single();
    }

    public List<Course> moderation(UUID actor) {
        admins.require(actor, AdminGrants.Permission.EDUCATION_OPERATIONS);
        return db.sql(COURSES + " where c.status in ('PENDING_REVIEW','PUBLISHED','REJECTED','SUSPENDED') order by (c.status='PENDING_REVIEW') desc,c.title,c.id limit 100")
                .query(Course.class).list();
    }

    @Transactional
    public Course moderate(UUID actor, UUID id, Decision decision, String reason) {
        admins.require(actor, AdminGrants.Permission.EDUCATION_OPERATIONS);
        if (decision == Decision.PUBLISH) requireEnabled();
        course(id);
        switch (decision) {
            case PUBLISH -> transition(id, "PUBLISHED", "PENDING_REVIEW", "PENDING_REVIEW");
            case REJECT -> transition(id, "REJECTED", "PENDING_REVIEW", "PENDING_REVIEW");
            case SUSPEND -> transition(id, "SUSPENDED", "PUBLISHED", "PUBLISHED");
        }
        event(id, actor, decision.name(), reason.strip());
        return course(id);
    }

    public List<Session> instructorSessions(UUID actor) {
        var partnerIds = partnerDirectory.approvedPartnersOfStaff(actor);
        if (partnerIds.isEmpty()) return List.of();
        return db.sql(SESSIONS + """
                where h.instructor_id=:actor and c.status='PUBLISHED' and c.partner_id in (:partners)
                order by h.starts_at desc,h.id limit 100
                """).param("actor", actor).param("partners", partnerIds).query(Session.class).list();
    }

    @Transactional
    public Learner attendance(UUID actor, UUID session, UUID enrollment, Attendance status) {
        var owner = db.sql("""
                select c.partner_id from marketplace.education_cohorts h
                join marketplace.education_courses c on c.id=h.course_id
                where h.id=:session and h.instructor_id=:actor and h.starts_at<=now() and c.status='PUBLISHED'
                for share of h,c
                """).param("session", session).param("actor", actor).query(UUID.class).optional()
                .orElseThrow(EducationOperationsService::notFound);
        partners.requireProcessing(actor, owner);
        var learner = db.sql("""
                update transactions.education_enrollments set attendance=:status
                where id=:id and cohort_id=:session returning id,attendance,null as response,null as assignment_status,null as feedback
                """).param("id", enrollment).param("session", session).param("status", status.name())
                .query(Learner.class).optional().orElseThrow(EducationOperationsService::notFound);
        UUID course = db.sql("select course_id from marketplace.education_cohorts where id=:session")
                .param("session", session).query(UUID.class).single();
        event(course, actor, "ATTENDANCE_" + status.name(), enrollment.toString());
        return learner;
    }

    public List<Learner> roster(UUID actor, UUID session) {
        UUID partner = db.sql("""
                select c.partner_id from marketplace.education_cohorts h
                join marketplace.education_courses c on c.id=h.course_id and c.status='PUBLISHED'
                where h.id=:session and h.instructor_id=:actor
                """).param("actor", actor).param("session", session).query(UUID.class).optional()
                .orElseThrow(EducationOperationsService::notFound);
        if (!partnerDirectory.isActiveStaffOfApprovedPartner(actor, partner)) throw notFound();
        return db.sql("""
                select e.id,e.attendance,s.response,s.status as assignment_status,s.feedback
                from transactions.education_enrollments e
                left join transactions.education_assignment_submissions s on s.enrollment_id=e.id
                where e.cohort_id=:session order by e.created_at,e.id
                """)
                .param("session", session).query(Learner.class).list();
    }

    private void manage(UUID actor, UUID partner) {
        partners.requireProcessing(actor, partner, Role.OWNER, Role.MANAGER);
        requireEnabled();
    }

    private void requireEnabled() {
        if (!toggles.enabled(FeatureToggles.Feature.EDUCATION)) {
            throw conflict("EDUCATION_UNAVAILABLE", "Education intake is disabled");
        }
    }

    private void ownCourse(UUID partner, UUID id) {
        if (!course(id).partnerId().equals(partner)) throw notFound();
    }

    private Course course(UUID id) {
        return db.sql(COURSES + " where c.id=:id").param("id", id).query(Course.class).optional()
                .orElseThrow(EducationOperationsService::notFound);
    }

    private void transition(UUID id, String next, String from, String alternative) {
        if (db.sql("update marketplace.education_courses set status=:next where id=:id and status in (:from,:alternative)")
                .param("id", id).param("next", next).param("from", from).param("alternative", alternative).update() == 0) {
            throw conflict("COURSE_STATE_CHANGED", "The course state does not allow this action");
        }
    }

    private void event(UUID id, UUID actor, String action, String reason) {
        db.sql("""
                insert into marketplace.education_course_events(course_id,actor_user_id,action,reason)
                values (:id,:actor,:action,:reason)
                """).param("id", id).param("actor", actor).param("action", action).param("reason", reason).update();
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "EDUCATION_RESOURCE_NOT_FOUND", "Resource not found");
    }

    private static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    public enum Decision { PUBLISH, REJECT, SUSPEND }
    public enum Attendance { PRESENT, ABSENT }
    public record Course(UUID id, UUID partnerId, String title, String description, String status, String organization, String format) {}
    public record Instructor(UUID id, String name) {}
    public record Learner(UUID id, String attendance, String response, String assignmentStatus, String feedback) {}
    public record Session(UUID id, UUID courseId, String title, String format, OffsetDateTime startsAt,
            OffsetDateTime endsAt, int capacity, UUID instructorId) {}
    public record Draft(@NotBlank @Size(max=180) String title, @NotBlank @Size(max=5000) String description,
            @NotBlank @Size(max=48) String category, @NotBlank @Size(max=100) String city,
            @NotBlank @Size(max=8) String language, @NotNull EducationCatalogController.Format format,
            @NotNull @Min(0) Long priceMinor, @NotNull @Min(1) @Max(100000) Integer durationMinutes, @Size(max=12000) String recordedText,
            @Size(max=1500) String assignmentPrompt, @Valid QuizInput quiz) {}
    public record QuizInput(@NotBlank @Size(max=300) String question,
            @NotNull @Size(min=2, max=6) List<@NotBlank @Size(max=500) String> choices,
            @NotNull @Min(0) @Max(5) Integer correctChoice, @NotNull @Min(1) @Max(10) Integer maxAttempts) {}
    public record CohortInput(@NotNull EducationCatalogController.Format format, OffsetDateTime startsAt,
            OffsetDateTime endsAt, @NotNull @Min(1) @Max(1000) Integer capacity, UUID instructorId) {}
}
