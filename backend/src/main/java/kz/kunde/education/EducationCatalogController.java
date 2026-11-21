package kz.kunde.education;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

@RestController
@Validated
@RequestMapping("/api/v1/education")
public class EducationCatalogController {
    private static final String PUBLISHED = """
            from marketplace.education_courses c
            join marketplace.partners p on p.id = c.partner_id
            where c.status = 'PUBLISHED' and p.verification_status = 'APPROVED'
            """;

    private final JdbcClient db;
    private final FeatureToggles toggles;

    private final EducationEnrollmentService enrollments;

    public EducationCatalogController(JdbcClient db, FeatureToggles toggles, EducationEnrollmentService enrollments) {
        this.db = db;
        this.toggles = toggles;
        this.enrollments = enrollments;
    }

    @GetMapping("/courses")
    ResponseEntity<CoursePage> courses(
            @RequestParam(defaultValue = "") @Size(max = 120) String q,
            @RequestParam(defaultValue = "") @Size(max = 48) String category,
            @RequestParam(defaultValue = "") @Size(max = 100) String city,
            @RequestParam(required = false) Format format,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        requireEnabled();
        var items = db.sql("""
                select c.id, c.title, c.category, c.city, c.language, p.display_name, c.synthetic,
                    (select min(f.price_minor) from marketplace.education_course_formats f
                     where f.course_id = c.id and (:format = '' or f.format = :format)) as price_minor
                """ + PUBLISHED + """
                and (:q = '' or strpos(lower(c.title), lower(:q)) > 0
                    or strpos(lower(c.description), lower(:q)) > 0
                    or strpos(lower(p.display_name), lower(:q)) > 0
                    or strpos(lower(c.category), lower(:q)) > 0)
                and (:category = '' or c.category = :category)
                and (:city = '' or lower(c.city) = lower(:city))
                and exists (select 1 from marketplace.education_course_formats f
                            where f.course_id = c.id and (:format = '' or f.format = :format))
                order by c.title, c.id
                limit :limit offset :offset
                """)
                .param("q", q.strip()).param("category", category.strip()).param("city", city.strip())
                .param("format", format == null ? "" : format.name()).param("limit", limit + 1).param("offset", offset)
                .query((rs, row) -> course(rs)).list();
        return noStore(new CoursePage(items.stream().limit(limit).toList(), items.size() > limit));
    }

    @GetMapping("/courses/{id}/cohorts")
    ResponseEntity<List<EducationEnrollmentService.Cohort>> cohorts(@PathVariable UUID id) {
        return noStore(enrollments.cohorts(id));
    }

    @GetMapping("/certificates/{code}")
    ResponseEntity<EducationEnrollmentService.Certificate> certificate(@PathVariable UUID code) {
        return noStore(enrollments.certificate(code));
    }

    @GetMapping("/courses/{id}")
    @Transactional(readOnly = true, isolation = org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
    public ResponseEntity<CourseDetail> course(@PathVariable UUID id) {
        requireEnabled();
        var header = db.sql("""
                select c.id, c.title, c.category, c.city, c.language, p.display_name, c.synthetic, description,
                    (select min(f.price_minor) from marketplace.education_course_formats f
                     where f.course_id = c.id) as price_minor
                """ + PUBLISHED + " and c.id = :id")
                .param("id", id)
                .query((rs, row) -> new Header(course(rs), rs.getString("description"))).optional()
                .filter(value -> value.course().priceMinor() != null)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "COURSE_NOT_FOUND", "Course not found"));
        var formats = db.sql("""
                select format, price_minor, duration_minutes from marketplace.education_course_formats
                where course_id = :id order by format
                """).param("id", id)
                .query((rs, row) -> new CourseFormat(Format.valueOf(rs.getString(1)), rs.getLong(2), rs.getInt(3))).list();
        var lessons = db.sql("""
                select module_position, position, title, duration_minutes from marketplace.education_course_lessons
                where course_id = :id order by module_position, position
                """).param("id", id)
                .query((rs, row) -> new Lesson(rs.getInt(1), rs.getInt(2), rs.getString(3), rs.getInt(4))).list();
        var modules = db.sql("""
                select position, title from marketplace.education_course_modules where course_id = :id order by position
                """).param("id", id)
                .query((rs, row) -> new Module(rs.getInt(1), rs.getString(2), List.of())).list();
        return noStore(new CourseDetail(header.course(), header.description(), formats, modules.stream()
                .map(module -> new Module(module.position(), module.title(), lessons.stream()
                        .filter(lesson -> lesson.modulePosition() == module.position()).toList())).toList()));
    }

    private void requireEnabled() {
        if (!toggles.enabled(FeatureToggles.Feature.EDUCATION)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "EDUCATION_UNAVAILABLE", "Education is unavailable");
        }
    }

    private static CourseCard course(ResultSet rs) throws SQLException {
        return new CourseCard(rs.getObject("id", UUID.class), rs.getString("title"), rs.getString("category"),
                rs.getString("city"), rs.getString("language"), rs.getString("display_name"),
                rs.getObject("price_minor", Long.class), rs.getBoolean("synthetic"));
    }

    private static <T> ResponseEntity<T> noStore(T value) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(value);
    }

    public enum Format { ONLINE_RECORDED, ONLINE_LIVE, OFFLINE_GROUP, OFFLINE_INDIVIDUAL, HYBRID }
    public record CourseCard(UUID id, String title, String category, String city, String language, String organization,
            Long priceMinor, boolean synthetic) {}
    public record CoursePage(List<CourseCard> items, boolean hasMore) {}
    public record CourseFormat(Format format, long priceMinor, int durationMinutes) {}
    public record Lesson(int modulePosition, int position, String title, int durationMinutes) {}
    public record Module(int position, String title, List<Lesson> lessons) {}
    public record CourseDetail(CourseCard course, String description, List<CourseFormat> formats, List<Module> modules) {}
    private record Header(CourseCard course, String description) {}
}
