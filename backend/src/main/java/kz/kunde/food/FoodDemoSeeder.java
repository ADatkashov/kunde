package kz.kunde.food;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
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
 * Safe, repeatable DEV seed of clearly synthetic restaurants and menus (food/demo-catalog.json). Runs only when
 * {@code app.food.seed-demo=true}, which {@link FoodGuard} allows only in dev/local/test. A restaurant that
 * already exists (by slug) is never touched, so owner edits and orders are preserved and the seed is idempotent.
 * No real businesses, prices or partners are represented; no users or personal data are created.
 */
@Component
@ConditionalOnProperty(name = "app.food.seed-demo", havingValue = "true")
public class FoodDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(FoodDemoSeeder.class);
    private final JdbcTemplate db;

    public FoodDemoSeeder(JdbcTemplate db) { this.db = db; }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        try (InputStream in = new ClassPathResource("food/demo-catalog.json").getInputStream()) {
            int inserted = seed(new ObjectMapper().readTree(in));
            log.info("Food demo seed: {} synthetic restaurants inserted", inserted);
        }
    }

    @Transactional
    public int seed(JsonNode catalog) {
        int inserted = 0;
        int order = 0;
        for (JsonNode r : catalog.get("restaurants")) {
            order++;
            UUID id = db.query("""
                    insert into marketplace.food_restaurants (slug, name, cuisine, description, emoji, tone,
                        delivery_fee_minor, min_order_minor, eta_min_minutes, eta_max_minutes, is_open, is_synthetic, sort_order)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, true, ?) on conflict (slug) do nothing returning id
                    """, rs -> rs.next() ? rs.getObject(1, UUID.class) : null, r.get("slug").asText(),
                    r.get("name").asText(), r.get("cuisine").asText(), r.get("description").asText(), r.get("emoji").asText(),
                    r.get("tone").asText(), r.get("deliveryFee").asLong(), r.get("minOrder").asLong(),
                    r.get("etaMin").asInt(), r.get("etaMax").asInt(), r.get("open").asBoolean(), order);
            if (id == null) { continue; }
            inserted++;
            int sectionOrder = 0;
            for (JsonNode s : r.get("sections")) {
                UUID sectionId = db.queryForObject("""
                        insert into marketplace.food_menu_sections (restaurant_id, name, sort_order) values (?, ?, ?) returning id
                        """, UUID.class, id, s.get("name").asText(), sectionOrder++);
                int dishOrder = 0;
                for (JsonNode d : s.get("dishes")) {
                    UUID dishId = db.queryForObject("""
                            insert into marketplace.food_dishes (restaurant_id, section_id, name, description, price_minor,
                                emoji, tone, available, sort_order) values (?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                            """, UUID.class, id, sectionId, d.get("name").asText(), d.get("description").asText(),
                            d.get("price").asLong(), d.get("emoji").asText(), d.get("tone").asText(),
                            d.get("available").asBoolean(), dishOrder++);
                    int groupOrder = 0;
                    for (JsonNode g : d.get("groups")) {
                        UUID groupId = db.queryForObject("""
                                insert into marketplace.food_option_groups (dish_id, name, min_select, max_select, sort_order)
                                values (?, ?, ?, ?, ?) returning id
                                """, UUID.class, dishId, g.get("name").asText(), g.get("min").asInt(), g.get("max").asInt(), groupOrder++);
                        int optionOrder = 0;
                        for (JsonNode o : g.get("options")) {
                            db.update("insert into marketplace.food_options (group_id, name, price_delta_minor, sort_order) values (?, ?, ?, ?)",
                                    groupId, o.get("name").asText(), o.get("delta").asLong(), optionOrder++);
                        }
                    }
                }
            }
        }
        return inserted;
    }
}
