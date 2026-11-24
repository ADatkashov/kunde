package kz.kunde.health;

import com.fasterxml.jackson.databind.ObjectMapper;
import kz.kunde.booking.BookingDemoSeeder;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@Order(110)
@ConditionalOnProperty(name = "app.health.seed-demo", havingValue = "true")
public class HealthDemoSeeder implements ApplicationRunner {
    private final JdbcTemplate db;

    public HealthDemoSeeder(JdbcTemplate db) {
        this.db = db;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) throws Exception {
        try (var stream = new ClassPathResource("health/demo-venues.json").getInputStream()) {
            new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(stream));
        }
        db.update("""
                update marketplace.booking_venues health
                set partner_id = demo.partner_id
                from marketplace.booking_venues demo
                where demo.slug = 'partner-salon-demo' and demo.is_synthetic and demo.partner_id is not null
                  and health.slug like 'health-demo-%' and health.is_synthetic and health.category = 'HEALTH'
                  and health.partner_id is null
                """);
    }
}
