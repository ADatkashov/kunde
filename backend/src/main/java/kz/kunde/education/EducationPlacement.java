package kz.kunde.education;

import kz.kunde.platform.placement.PlacementLocator;
import kz.kunde.platform.placement.SqlPlacementLocator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Placement of Education aggregates: the course is the root (city_id); cohorts and enrolments inherit it. */
@Configuration(proxyBeanMethods = false)
class EducationPlacement {
    @Bean
    PlacementLocator educationCoursePlacement(JdbcTemplate db) {
        return new SqlPlacementLocator("education.course", "education",
                "select city_id from marketplace.education_courses where id = ?", db);
    }
}
