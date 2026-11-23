package kz.kunde.booking;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import java.sql.Array;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Repeatable DEV seed of clearly synthetic Beauty salons (beauty/demo-salons.json) on top of the Booking engine seed:
 * venues, services, masters and schedules come from {@link BookingDemoSeeder#seed}; this adds profiles, service details,
 * masters' specialty, synthetic reviews and promotions. Runs only with {@code app.beauty.seed-demo=true} and only where
 * Beauty is allowed (dev/local/test). A salon that already exists (by slug) is never touched; no users or bookings are created.
 */
@Component
@org.springframework.core.annotation.Order(11)
@ConditionalOnProperty(name = "app.beauty.seed-demo", havingValue = "true")
public class BeautyDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(BeautyDemoSeeder.class);
    private final JdbcTemplate db;
    private final BeautySettings settings;

    public BeautyDemoSeeder(JdbcTemplate db, BeautySettings settings) {
        this.db = db;
        this.settings = settings;
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        if (!settings.allowedByEnvironment()) {
            log.warn("Beauty demo seed skipped: Beauty is not allowed in this environment");
            return;
        }
        try (InputStream in = new ClassPathResource("beauty/demo-salons.json").getInputStream()) {
            log.info("Beauty demo seed: {} synthetic salons inserted", seed(new ObjectMapper().readTree(in)));
        }
    }

    @Transactional
    public int seed(JsonNode catalog) {
        int inserted = new BookingDemoSeeder(db).seed(catalog);
        for (JsonNode v : catalog.get("venues")) {
            UUID venueId = db.queryForObject("select id from marketplace.booking_venues where slug = ?", UUID.class, v.get("slug").asText());
            JsonNode b = v.get("beauty");
            int created = db.update("""
                    insert into marketplace.beauty_salon_profiles (venue_id, category_codes, latitude, longitude, verified, phone, cancellation_policy)
                    values (?, ?::text[], ?, ?, ?, ?, ?) on conflict (venue_id) do nothing
                    """, venueId, textArray(b.get("categories")), b.get("lat").decimalValue(), b.get("lng").decimalValue(),
                    b.get("verified").asBoolean(), b.get("phone").asText(), b.get("cancellation").asText());
            if (created == 0) { continue; }
            for (JsonNode s : v.get("services")) {
                JsonNode sb = s.get("beauty");
                db.update("""
                        insert into marketplace.beauty_service_profiles (service_id, category_code, tags, includes, preparation, price_from)
                        select id, ?, ?::text[], ?::text[], ?, ? from marketplace.booking_services where venue_id = ? and name = ?
                        on conflict (service_id) do nothing
                        """, sb.get("category").asText(), textArray(sb.get("tags")), textArray(sb.get("includes")),
                        sb.get("preparation").asText(), sb.get("priceFrom").asBoolean(), venueId, s.get("name").asText());
            }
            for (JsonNode m : v.get("masters")) {
                db.update("update marketplace.booking_masters set specialty = ?, experience_years = ? where venue_id = ? and name = ?",
                        m.get("specialty").asText(), m.get("experience").asInt(), venueId, m.get("name").asText());
            }
            int age = 0;
            for (JsonNode r : v.get("reviews")) {
                age += 3;
                db.update("""
                        insert into marketplace.beauty_reviews (venue_id, master_id, service_id, author_name, rating, comment, synthetic, created_at)
                        values (?, (select id from marketplace.booking_masters where venue_id = ? and name = ?),
                                (select id from marketplace.booking_services where venue_id = ? and name = ?), ?, ?, ?, true,
                                now() - make_interval(days => ?))
                        """, venueId, venueId, r.get("master").asText(), venueId, r.get("service").asText(), r.get("author").asText(),
                        r.get("rating").asInt(), r.get("comment").asText(), age);
            }
            for (JsonNode p : v.get("promotions")) {
                db.update("""
                        insert into marketplace.beauty_promotions (venue_id, title, percent, ends_at, synthetic)
                        values (?, ?, ?, now() + make_interval(days => ?), true)
                        """, venueId, p.get("title").asText(), p.get("percent").asInt(), p.get("days").asInt());
            }
        }
        return inserted;
    }

    private static String textArray(JsonNode values) {
        List<String> items = new ArrayList<>();
        values.forEach(n -> items.add("\"" + n.asText().replace("\\", "\\\\").replace("\"", "\\\"") + "\""));
        return "{" + String.join(",", items) + "}";
    }
}
