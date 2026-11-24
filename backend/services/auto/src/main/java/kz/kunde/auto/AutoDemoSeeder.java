package kz.kunde.auto;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import kz.kunde.booking.BookingDemoSeeder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** DEV-only synthetic car services (auto/demo-venues.json); never touches an existing venue, creates no users or bookings. */
@Component
@Order(11)
@ConditionalOnProperty(name = "app.auto.seed-demo", havingValue = "true")
public class AutoDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(AutoDemoSeeder.class);
    private final JdbcTemplate db;

    public AutoDemoSeeder(JdbcTemplate db) { this.db = db; }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        try (InputStream in = new ClassPathResource("auto/demo-venues.json").getInputStream()) {
            log.info("Auto demo seed: {} synthetic venues inserted", new BookingDemoSeeder(db).seed(new ObjectMapper().readTree(in)));
        }
    }
}
