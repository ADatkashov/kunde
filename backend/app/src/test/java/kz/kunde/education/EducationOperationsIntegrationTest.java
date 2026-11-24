package kz.kunde.education;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import kz.kunde.education.EducationCatalogController.Format;
import kz.kunde.education.EducationOperationsService.Attendance;
import kz.kunde.education.EducationOperationsService.CohortInput;
import kz.kunde.education.EducationOperationsService.Decision;
import kz.kunde.education.EducationOperationsService.Draft;
import kz.kunde.education.EducationOperationsService.QuizInput;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = "app.environment=test")
@Transactional
class EducationOperationsIntegrationTest {
    @Autowired JdbcTemplate db;
    @Autowired EducationOperationsService operations;
    @Autowired EducationEnrollmentService enrollments;

    @Test
    void tenantCreatesCourseModeratorPublishesAndOnlyAssignedInstructorMarksAttendance() {
        UUID owner = user();
        UUID stranger = user();
        UUID instructor = user();
        UUID admin = user();
        UUID partner = partner(owner);
        UUID otherPartner = partner(stranger);
        db.update("insert into marketplace.partner_staff(partner_id,user_id,role,granted_by_user_id) values (?,?,'OPERATOR',?)",
                partner, instructor, owner);
        db.update("insert into identity.admin_grants(user_id,permission,reason) values (?,'EDUCATION_OPERATIONS','Synthetic course moderation')", admin);
        var draft = operations.create(owner, partner,
                new Draft("Synthetic workshop", "Practice", "IT", "Алматы", "ru", Format.OFFLINE_GROUP, 750L, 40, null, null, null));
        assertThat(draft.status()).isEqualTo("DRAFT");
        assertThat(operations.partnerCourses(stranger, otherPartner)).isEmpty();
        assertThatThrownBy(() -> operations.submit(stranger, otherPartner, draft.id())).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> operations.moderation(stranger)).isInstanceOf(ApiException.class);
        var start = OffsetDateTime.now().plusDays(3);
        var session = operations.createSession(owner, partner, draft.id(),
                new CohortInput(Format.OFFLINE_GROUP, start, start.plusMinutes(40), 2, instructor));
        assertThat(enrollments.cohorts(draft.id())).isEmpty();
        assertThat(operations.submit(owner, partner, draft.id()).status()).isEqualTo("PENDING_REVIEW");
        assertThat(operations.moderation(admin)).anyMatch(row -> row.id().equals(draft.id()));
        assertThat(operations.moderate(admin, draft.id(), Decision.PUBLISH, "Synthetic pilot approved").status()).isEqualTo("PUBLISHED");
        assertThat(enrollments.cohorts(draft.id())).hasSize(1);
        var entry = enrollments.enroll(stranger, session.id(), 750, "test-workshop-0001").enrollment();
        assertThat(operations.instructorSessions(instructor)).hasSize(1);
        assertThat(operations.instructorSessions(stranger)).isEmpty();
        assertThatThrownBy(() -> operations.roster(stranger, session.id())).isInstanceOf(ApiException.class);
        assertThat(operations.roster(instructor, session.id())).extracting(EducationOperationsService.Learner::id).containsExactly(entry.id());
        assertThatThrownBy(() -> operations.attendance(instructor, session.id(), entry.id(), Attendance.PRESENT))
                .isInstanceOf(ApiException.class);
        db.update("update marketplace.education_cohorts set starts_at=now()-interval '1 hour' where id=?", session.id());
        assertThat(operations.attendance(instructor, session.id(), entry.id(), Attendance.PRESENT).attendance()).isEqualTo("PRESENT");
        assertThat(db.queryForObject("select count(*) from marketplace.education_course_events where course_id=?", Integer.class, draft.id()))
                .isEqualTo(5);
    }

    @Test
    void assignedInstructorCanReviewTextAssignmentAndCompletionRequiresPartnerQuiz() {
        UUID instructor = user();
        UUID student = user();
        UUID stranger = user();
        UUID partner = partner(instructor);
        var draft = operations.create(instructor, partner,
                new Draft("Recorded workshop", "Practice", "IT", "Алматы", "ru",
                        Format.ONLINE_RECORDED, 700L, 40, "Learn about loops", "Describe a loop",
                        new QuizInput("What repeats?", List.of("A loop", "A number"), 0, 2)));
        var session = operations.createSession(instructor, partner, draft.id(),
                new CohortInput(Format.ONLINE_RECORDED, null, null, 2, instructor));
        db.update("update marketplace.education_courses set status='PUBLISHED' where id=?", draft.id());
        UUID id = enrollments.enroll(student, session.id(), 700, "test-assignment-0001").enrollment().id();
        assertThat(enrollments.completeLesson(student, id, 1, 1).enrollment().certificateCode()).isNull();
        assertThat(enrollments.submitAssignment(student, id, "A loop executes repeatedly").assignment().status())
                .isEqualTo("SUBMITTED");
        assertThatThrownBy(() -> enrollments.reviewAssignment(stranger, session.id(), id, true, "OK"))
                .isInstanceOf(ApiException.class);
        assertThat(enrollments.reviewAssignment(instructor, session.id(), id, false, "Add an example").status())
                .isEqualTo("RETURNED");
        assertThat(enrollments.submitAssignment(student, id, "For each number, print it").assignment().status())
                .isEqualTo("SUBMITTED");
        assertThat(enrollments.reviewAssignment(instructor, session.id(), id, true, "Good example").status())
                .isEqualTo("APPROVED");
        var learning = enrollments.learning(student, id);
        assertThat(learning.enrollment().certificateCode()).isNull();
        assertThat(learning.quiz().choices()).containsExactly("A loop", "A number");
        assertThat(enrollments.attemptQuiz(student, id, UUID.randomUUID(), 0).enrollment().certificateCode())
                .isNotNull();
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID partner(UUID owner) {
        UUID partner = db.queryForObject("""
                insert into marketplace.partners(display_name,verification_status,created_by_user_id)
                values ('Synthetic Education studio','APPROVED',?) returning id
                """, UUID.class, owner);
        db.update("insert into marketplace.partner_staff(partner_id,user_id,role,granted_by_user_id) values (?,?,'OWNER',?)",
                partner, owner, owner);
        return partner;
    }
}
