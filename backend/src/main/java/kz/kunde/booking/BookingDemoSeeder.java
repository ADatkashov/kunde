package kz.kunde.booking;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
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
 * Safe, repeatable DEV seed of clearly synthetic barbershops, services, masters and weekly schedules
 * (booking/demo-venues.json). Runs only with {@code app.booking.seed-demo=true} (dev/local/test only, see
 * {@link BookingGuard}). A venue that already exists (by slug) is never touched; no users or bookings are created.
 */
@Component
@org.springframework.core.annotation.Order(10)
@ConditionalOnProperty(name = "app.booking.seed-demo", havingValue = "true")
public class BookingDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(BookingDemoSeeder.class);
    private final JdbcTemplate db;

    public BookingDemoSeeder(JdbcTemplate db) { this.db = db; }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        for (String file : new String[] {"booking/demo-venues.json", "booking/partner-demo-venues.json"}) {
            try (InputStream in = new ClassPathResource(file).getInputStream()) {
                log.info("Booking demo seed {}: {} synthetic venues inserted", file, seed(new ObjectMapper().readTree(in)));
            }
        }
    }

    @Transactional
    public int seed(JsonNode catalog) {
        int inserted = 0;
        int order = 0;
        for (JsonNode v : catalog.get("venues")) {
            order++;
            UUID venueId = db.query("""
                    insert into marketplace.booking_venues (slug, category, name, description, address_text, emoji, tone,
                        is_open, is_synthetic, sort_order, buffer_minutes) values (?, ?, ?, ?, ?, ?, ?, ?, true, ?, ?)
                    on conflict (slug) do nothing returning id
                    """, rs -> rs.next() ? rs.getObject(1, UUID.class) : null, v.get("slug").asText(),
                    v.get("category").asText(), v.get("name").asText(), v.get("description").asText(),
                    v.get("address").asText(), v.get("emoji").asText(), v.get("tone").asText(), v.get("open").asBoolean(), order,
                    v.has("bufferMinutes") ? v.get("bufferMinutes").asInt() : 0);
            if (venueId == null) { continue; }
            inserted++;
            Map<String, UUID> serviceIds = new HashMap<>();
            int serviceOrder = 0;
            for (JsonNode s : v.get("services")) {
                serviceIds.put(s.get("name").asText(), db.queryForObject("""
                        insert into marketplace.booking_services (venue_id, name, description, duration_minutes, price_minor, sort_order,
                            price_per_sqm_minor, min_area_sqm, max_area_sqm, auto_category, price_kind, conditions, health_category)
                        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                        """, UUID.class, venueId, s.get("name").asText(), s.get("description").asText(),
                        s.get("duration").asInt(), s.get("price").asLong(), serviceOrder++,
                        s.has("pricePerSqm") ? s.get("pricePerSqm").asLong() : 0L,
                        s.has("minArea") ? s.get("minArea").asInt() : null,
                        s.has("maxArea") ? s.get("maxArea").asInt() : null,
                        s.has("autoCategory") ? s.get("autoCategory").asText() : null,
                        s.has("priceKind") ? s.get("priceKind").asText() : "FIXED",
                        s.has("conditions") ? s.get("conditions").asText() : "",
                        s.has("healthCategory") ? s.get("healthCategory").asText() : null));
            }
            int masterOrder = 0;
            for (JsonNode m : v.get("masters")) {
                UUID masterId = db.queryForObject("""
                        insert into marketplace.booking_masters (venue_id, name, bio, emoji, tone, sort_order)
                        values (?, ?, ?, ?, ?, ?) returning id
                        """, UUID.class, venueId, m.get("name").asText(), m.get("bio").asText(), m.get("emoji").asText(),
                        m.get("tone").asText(), masterOrder++);
                for (JsonNode serviceName : m.get("services")) {
                    db.update("insert into marketplace.booking_master_services (master_id, service_id) values (?, ?)",
                            masterId, serviceIds.get(serviceName.asText()));
                }
                for (JsonNode h : m.get("hours")) {
                    db.update("""
                            insert into marketplace.booking_working_hours (master_id, weekday, start_time, end_time, break_start, break_end)
                            values (?, ?, ?::time, ?::time, ?::time, ?::time)
                            """, masterId, h.get("day").asInt(), h.get("from").asText(), h.get("to").asText(),
                            h.has("breakFrom") ? h.get("breakFrom").asText() : null,
                            h.has("breakTo") ? h.get("breakTo").asText() : null);
                }
            }
        }
        return inserted;
    }
}
