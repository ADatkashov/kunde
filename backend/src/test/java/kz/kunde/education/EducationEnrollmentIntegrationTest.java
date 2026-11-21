package kz.kunde.education;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import kz.kunde.platform.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest(properties = {"app.environment=test", "app.identity.consumer-enabled=true",
        "app.auth.phone.enabled=true", "app.auth.phone.secret=synthetic-test-secret-synthetic-test-secret",
        "app.auth.phone.dev-otp.enabled=true", "app.auth.phone.dev-otp.allowed-phones=+77000000691"})
@AutoConfigureMockMvc
class EducationEnrollmentIntegrationTest {
    @Autowired EducationEnrollmentService enrollment;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc http;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactionManager;

    @Test
    @Transactional
    void captureAndLearningAreIdempotentAndPrivate() throws Exception {
        UUID user = user();
        UUID other = user();
        UUID cohort = cohort(1);
        assertThatThrownBy(() -> enrollment.enroll(user, cohort, 749, "student-request-0000"))
                .isInstanceOf(ApiException.class).hasMessageContaining("price changed");
        // The rejected service transaction would be rolled back on an ordinary HTTP request.
        var result = enrollment.enroll(user, cohort, 750, "student-request-0001");
        var id = result.enrollment().id();
        assertThat(result.enrollment().paymentStatus()).isEqualTo("TEST_CAPTURED");
        assertThat(enrollment.enroll(user, cohort, 750, "student-request-0001").created()).isFalse();
        assertThat(enrollment.history(user, 30, 0)).hasSize(1);
        assertThat(enrollment.history(other, 30, 0)).isEmpty();
        assertThatThrownBy(() -> enrollment.learning(other, id)).isInstanceOf(ApiException.class);
        assertThat(enrollment.learning(user, id).lessons().get(1).content()).isNull();
        assertThatThrownBy(() -> enrollment.completeLesson(user, id, 1, 2)).isInstanceOf(ApiException.class);
        var continued = enrollment.completeLesson(user, id, 1, 1);
        assertThat(continued.enrollment().certificateCode()).isNull();
        assertThat(continued.lessons().get(1).content()).isNotBlank();
        UUID code = enrollment.completeLesson(user, id, 1, 2).enrollment().certificateCode();
        assertThat(code).isNotNull();
        assertThat(enrollment.completeLesson(user, id, 1, 2).enrollment().certificateCode()).isEqualTo(code);
        assertThat(enrollment.certificate(code).title()).isEqualTo("Synthetic course");
        http.perform(get("/api/v1/education/certificates/{code}", code)).andExpect(status().isOk());
        http.perform(get("/api/v1/education/enrollments/{id}/learning", id)).andExpect(status().isUnauthorized());
    }

    @Test
    @Transactional
    void signedInConsumerCanListAndEnrollThroughHttp() throws Exception {
        UUID cohort = cohort(2);
        UUID course = db.queryForObject("select course_id from marketplace.education_cohorts where id=?", UUID.class, cohort);
        http.perform(get("/api/v1/education/courses/{id}/cohorts", course)).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].remaining").value(2));
        http.perform(post("/api/v1/auth/otp/request").contentType("application/json")
                .content("{\"phone\":\"+77000000691\"}")).andExpect(status().isAccepted());
        String token = JsonPath.read(http.perform(post("/api/v1/auth/otp/verify").contentType("application/json")
                .content("{\"phone\":\"+77000000691\",\"code\":\"123456\"}")).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(), "$.accessToken");
        String payload = """
                {"cohortId":"%s","expectedPriceMinor":750,"paymentMethod":"TEST_CARD"}
                """.formatted(cohort);
        http.perform(post("/api/v1/education/enrollments").contentType("application/json")
                .header("Authorization", "Bearer " + token).header("Idempotency-Key", "test-http-enrollment-1")
                .content(payload)).andExpect(status().isCreated()).andExpect(jsonPath("$.status").value("CONFIRMED"))
                .andExpect(jsonPath("$.paymentStatus").value("TEST_CAPTURED"));
        http.perform(get("/api/v1/education/enrollments").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1));
        http.perform(post("/api/v1/education/enrollments").contentType("application/json")
                .header("Authorization", "Bearer " + token).header("Idempotency-Key", "test-http-enrollment-2")
                .content(payload)).andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("ALREADY_ENROLLED"));
    }

    @Test
    void twoCustomersCannotBothCaptureTheLastSeat() throws Exception {
        UUID cohort = cohort(1);
        UUID first = user();
        UUID second = user();
        try {
            try (var threads = Executors.newFixedThreadPool(2)) {
                var start = new java.util.concurrent.CountDownLatch(1);
                var attempts = List.of(first, second).stream().map(user -> threads.submit(() -> {
                    start.await();
                    try {
                        return enrollment.enroll(user, cohort, 750, "student-request-0002").created();
                    } catch (ApiException ex) {
                        assertThat(ex).hasMessageContaining("full");
                        return false;
                    }
                })).toList();
                start.countDown();
                assertThat(List.of(attempts.get(0).get(10, TimeUnit.SECONDS), attempts.get(1).get(10, TimeUnit.SECONDS)))
                        .containsExactlyInAnyOrder(true, false);
            }
            assertThat(db.queryForObject("""
                    select count(*) from transactions.education_payment_events p
                    join transactions.education_enrollments e on e.id=p.enrollment_id where e.cohort_id=?
                    """, Integer.class, cohort)).isEqualTo(1);
        } finally {
            cleanRaceFixture(cohort, first, second);
        }
    }

    private void cleanRaceFixture(UUID cohort, UUID first, UUID second) {
        new org.springframework.transaction.support.TransactionTemplate(transactionManager).executeWithoutResult(tx -> {
            UUID course = db.queryForObject("select course_id from marketplace.education_cohorts where id=?", UUID.class, cohort);
            UUID partner = db.queryForObject("select partner_id from marketplace.education_courses where id=?", UUID.class, course);
            UUID owner = db.queryForObject("select created_by_user_id from marketplace.partners where id=?", UUID.class, partner);
            // The test database owns this append-only fixture. DDL and targeted deletes are atomic.
            db.execute("alter table transactions.education_payment_events disable trigger education_payment_events_immutable");
            db.update("""
                    delete from transactions.education_payment_events where enrollment_id in
                    (select id from transactions.education_enrollments where cohort_id=?)
                    """, cohort);
            db.execute("alter table transactions.education_payment_events enable trigger education_payment_events_immutable");
            db.update("delete from transactions.education_enrollments where cohort_id=?", cohort);
            db.update("delete from marketplace.education_cohorts where id=?", cohort);
            db.update("delete from marketplace.education_course_lessons where course_id=?", course);
            db.update("delete from marketplace.education_course_modules where course_id=?", course);
            db.update("delete from marketplace.education_course_formats where course_id=?", course);
            db.update("delete from marketplace.education_courses where id=?", course);
            db.update("delete from marketplace.partners where id=?", partner);
            db.update("delete from identity.users where id in (?,?,?)", owner, first, second);
        });
    }

    private UUID user() {
        return db.queryForObject("insert into identity.users default values returning id", UUID.class);
    }

    private UUID cohort(int capacity) {
        UUID partner = db.queryForObject("""
                insert into marketplace.partners(display_name,verification_status,created_by_user_id)
                values ('Synthetic enrollment partner','APPROVED',?) returning id
                """, UUID.class, user());
        UUID course = UUID.randomUUID();
        db.update("""
                insert into marketplace.education_courses(id,partner_id,category,title,description,city,language,status,synthetic)
                values (?,?,'IT','Synthetic course','Synthetic content','Алматы','ru','PUBLISHED',true)
                """, course, partner);
        db.update("insert into marketplace.education_course_formats values (?,'ONLINE_RECORDED',750,40)", course);
        db.update("insert into marketplace.education_course_modules values (?,1,'Module')", course);
        db.update("insert into marketplace.education_course_lessons values (?,1,1,'Lesson 1',20,'First lesson'), (?,1,2,'Lesson 2',20,'Second lesson')", course, course);
        UUID cohort = UUID.randomUUID();
        db.update("insert into marketplace.education_cohorts(id,course_id,format,capacity,open) values (?,?,'ONLINE_RECORDED',?,true)", cohort, course, capacity);
        return cohort;
    }
}
