package kz.kunde.education;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;
import kz.kunde.platform.FeatureToggles;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@Transactional
@SpringBootTest(properties = "app.environment=test")
@AutoConfigureMockMvc
class EducationCatalogIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @Autowired FeatureToggles toggles;

    @AfterEach
    void clearToggleCache() {
        toggles.invalidate();
    }

    @Test
    void publishedCatalogIsSearchableAndDraftsAndSuspendedPartnersAreHidden() throws Exception {
        UUID owner = db.queryForObject("insert into identity.users default values returning id", UUID.class);
        UUID approved = partner(owner, "APPROVED");
        UUID suspended = partner(owner, "SUSPENDED");
        UUID published = course(approved, "PUBLISHED");
        UUID draft = course(approved, "DRAFT");
        UUID hidden = course(suspended, "PUBLISHED");
        db.update("insert into marketplace.education_course_modules values (?, 1, 'Python basics')", published);
        db.update("insert into marketplace.education_course_lessons values (?, 1, 1, 'Variables', 20)", published);
        db.update("insert into marketplace.education_course_formats values (?, 'ONLINE_LIVE', 800000, 120)", published);

        http.perform(get("/api/v1/capabilities")).andExpect(status().isOk())
                .andExpect(jsonPath("$.educationEnabled").value(true));
        http.perform(get("/api/v1/education/courses").param("q", "python").param("category", "IT")
                        .param("city", "Алматы").param("format", "ONLINE_LIVE"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].id").value(published.toString()))
                .andExpect(jsonPath("$.items[0].priceMinor").value(800000))
                .andExpect(jsonPath("$.hasMore").value(false));
        http.perform(get("/api/v1/education/courses/{id}", published)).andExpect(status().isOk())
                .andExpect(jsonPath("$.modules[0].lessons[0].title").value("Variables"));
        http.perform(get("/api/v1/education/courses/{id}", draft)).andExpect(status().isNotFound());
        http.perform(get("/api/v1/education/courses/{id}", hidden)).andExpect(status().isNotFound());
        http.perform(get("/api/v1/education/courses").param("q", "%")).andExpect(status().isOk())
                .andExpect(jsonPath("$.items").isEmpty());

        toggles.set(owner, FeatureToggles.Feature.EDUCATION, false, "Pause synthetic catalog", null);
        http.perform(get("/api/v1/capabilities")).andExpect(status().isOk())
                .andExpect(jsonPath("$.educationEnabled").value(false));
        http.perform(get("/api/v1/education/courses")).andExpect(status().isNotFound());
        http.perform(get("/api/v1/education/courses/{id}", published)).andExpect(status().isNotFound());
    }

    @Test
    void syntheticSeedIsRepeatableAndVisibleInTheCatalog() throws Exception {
        var env = new org.springframework.mock.env.MockEnvironment().withProperty("app.environment", "test");
        var seed = new EducationDemoSeeder(db, new EducationSettings(env));
        seed.run(null);
        seed.run(null);
        http.perform(get("/api/v1/education/courses").param("q", "Python").param("city", "Алматы"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].synthetic").value(true));
        http.perform(get("/api/v1/education/courses").param("city", "Алматы").param("limit", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.hasMore").value(true));
    }

    private UUID partner(UUID owner, String status) {
        return db.queryForObject("""
                insert into marketplace.partners (created_by_user_id, display_name, verification_status)
                values (?, 'Synthetic Education partner', ?) returning id
                """, UUID.class, owner, status);
    }

    private UUID course(UUID partner, String status) {
        UUID id = UUID.randomUUID();
        db.update("""
                insert into marketplace.education_courses (id, partner_id, title, category, description, city, language, status, synthetic)
                values (?, ?, 'Python basics (synthetic)', 'IT', 'Test course', 'Алматы', 'ru', ?, true)
                """, id, partner, status);
        db.update("insert into marketplace.education_course_formats values (?, 'ONLINE_RECORDED', 500000, 100)", id);
        return id;
    }
}
