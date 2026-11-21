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
@org.springframework.core.annotation.Order(10)
@ConditionalOnProperty(name = "app.food.seed-demo", havingValue = "true")
public class FoodDemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(FoodDemoSeeder.class);
    private final JdbcTemplate db;

    public FoodDemoSeeder(JdbcTemplate db) { this.db = db; }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        for (String file : new String[] {"food/demo-catalog.json", "food/grocery-demo-catalog.json", "food/partner-demo-catalog.json", "food/flowers-demo-catalog.json"}) {
            try (InputStream in = new ClassPathResource(file).getInputStream()) {
                int inserted = seed(new ObjectMapper().readTree(in));
                log.info("Demo seed {}: {} synthetic stores/restaurants inserted", file, inserted);
            }
        }
        seedPromotions();
    }

    /** Synthetic DEV promo codes (idempotent by code). They are labelled synthetic and never exist in production. */
    @Transactional
    public void seedPromotions() {
        db.update("""
                insert into marketplace.food_promotions (code, title, description, kind, value, min_subtotal_minor, ends_at, per_user_limit, banner, is_synthetic)
                select 'WELCOME10', 'Скидка 10% на первый заказ (DEV)', 'Тестовый промокод: 10% на блюда от 2000 ₸', 'PERCENT', 10, 200000,
                       now() + interval '365 days', 1, true, true
                where not exists (select 1 from marketplace.food_promotions where code = 'WELCOME10')""");
        db.update("""
                insert into marketplace.food_promotions (code, title, description, kind, value, min_subtotal_minor, ends_at, per_user_limit, banner, is_synthetic)
                select 'FIX500', 'Минус 500 ₸ (DEV)', 'Тестовый промокод: 500 ₸ при заказе от 4000 ₸', 'FIXED', 50000, 400000,
                       now() + interval '365 days', 5, false, true
                where not exists (select 1 from marketplace.food_promotions where code = 'FIX500')""");
    }

    /**
     * Brings attributes added after a restaurant was first seeded (unit, initial stock) onto the existing synthetic rows:
     * the unit is set when it differs, stock only when it has never been set. Prices, names and availability are untouched.
     */
    private void syncDishAttributes(JsonNode restaurant) {
        for (JsonNode s : restaurant.get("sections")) {
            for (JsonNode d : s.get("dishes")) {
                if (d.has("legacyName")) {
                    // The first DEV seed priced these per kg but named them "..., 1 кг" and counted pieces.
                    db.update("""
                            update marketplace.food_dishes set name = ?, description = ?, unit = ? where name = ? and restaurant_id =
                                (select id from marketplace.food_restaurants where slug = ? and is_synthetic)
                            """, d.get("name").asText(), d.get("description").asText(), d.get("unit").asText(),
                            d.get("legacyName").asText(), restaurant.get("slug").asText());
                }
                if (d.has("unit")) {
                    db.update("""
                            update marketplace.food_dishes set unit = ? where name = ? and unit <> ? and restaurant_id =
                                (select id from marketplace.food_restaurants where slug = ? and is_synthetic)
                            """, d.get("unit").asText(), d.get("name").asText(), d.get("unit").asText(), restaurant.get("slug").asText());
                }
                if (d.has("stock")) {
                    db.update("""
                            update marketplace.food_dishes set stock_qty = ? where name = ? and stock_qty is null and restaurant_id =
                                (select id from marketplace.food_restaurants where slug = ? and is_synthetic)
                            """, d.get("stock").asInt(), d.get("name").asText(), restaurant.get("slug").asText());
                }
            }
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
                        delivery_fee_minor, min_order_minor, eta_min_minutes, eta_max_minutes, is_open, is_synthetic, sort_order, vertical, image_url)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, true, ?, ?, ?) on conflict (slug) do nothing returning id
                    """, rs -> rs.next() ? rs.getObject(1, UUID.class) : null, r.get("slug").asText(),
                    r.get("name").asText(), r.get("cuisine").asText(), r.get("description").asText(), r.get("emoji").asText(),
                    r.get("tone").asText(), r.get("deliveryFee").asLong(), r.get("minOrder").asLong(),
                    r.get("etaMin").asInt(), r.get("etaMax").asInt(), r.get("open").asBoolean(), order,
                    r.has("vertical") ? r.get("vertical").asText() : "FOOD",
                    r.has("imageUrl") ? r.get("imageUrl").asText() : null);
            if (id == null) {
                syncDishAttributes(r);
                continue;
            }
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
                                emoji, tone, available, sort_order, unit, stock_qty, image_url)
                            values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id
                            """, UUID.class, id, sectionId, d.get("name").asText(), d.get("description").asText(),
                            d.get("price").asLong(), d.get("emoji").asText(), d.get("tone").asText(),
                            d.get("available").asBoolean(), dishOrder++, d.has("unit") ? d.get("unit").asText() : "PIECE",
                            d.has("stock") ? d.get("stock").asInt() : null, d.has("imageUrl") ? d.get("imageUrl").asText() : null);
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
