package kz.kunde.education;

import java.nio.charset.StandardCharsets;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@ConditionalOnProperty(name = "app.education.seed-demo", havingValue = "true")
public class EducationDemoSeeder implements ApplicationRunner {
    private final JdbcTemplate db;

    public EducationDemoSeeder(JdbcTemplate db, EducationSettings settings) {
        if (!settings.allowedByEnvironment()) {
            throw new IllegalStateException("Synthetic Education data requires Education enabled in local, dev or test");
        }
        this.db = db;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) throws Exception {
        db.execute(new ClassPathResource("education/demo-courses.sql").getContentAsString(StandardCharsets.UTF_8));
    }
}
