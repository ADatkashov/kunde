package kz.kunde.food;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Public read-only Food catalog: restaurants, menus, dishes, options and search. Only available when app.food.enabled. */
@RestController
@Validated
@RequestMapping("/api/v1/food")
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class FoodCatalogController {
    public record RestaurantSummary(String id, String slug, String name, String cuisine, String description,
            String emoji, String tone, long deliveryFeeMinor, long minOrderMinor, int etaMinMinutes,
            int etaMaxMinutes, boolean open, boolean synthetic, String vertical, String imageUrl) {}

    public record Option(String id, String name, long priceDeltaMinor) {}

    public record OptionGroup(String id, String name, int minSelect, int maxSelect, List<Option> options) {}

    /** unit PIECE or KG (price per kg, quantities in grams); maxQuantity is the per-line limit incl. stock. */
    public record Dish(String id, String name, String description, long priceMinor, String emoji, String tone,
            boolean available, List<OptionGroup> optionGroups, String unit, int maxQuantity, Integer stockQty,
            String imageUrl) {}

    public record Section(String id, String name, List<Dish> dishes) {}

    public record RestaurantDetail(RestaurantSummary restaurant, List<Section> sections) {}

    public record DishHit(String id, String name, String description, long priceMinor, String emoji, String tone,
            boolean available, String restaurantId, String restaurantName) {}

    public record SearchResult(List<RestaurantSummary> restaurants, List<DishHit> dishes) {}

    private final JdbcTemplate jdbc;

    public FoodCatalogController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    static final String RESTAURANT_SELECT = """
            select id, slug, name, cuisine, description, emoji, tone, delivery_fee_minor, min_order_minor,
                   eta_min_minutes, eta_max_minutes, is_open, is_synthetic, vertical, image_url
            from marketplace.food_restaurants
            """;

    static RestaurantSummary mapRestaurant(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new RestaurantSummary(rs.getString("id"), rs.getString("slug"), rs.getString("name"),
                rs.getString("cuisine"), rs.getString("description"), rs.getString("emoji"), rs.getString("tone"),
                rs.getLong("delivery_fee_minor"), rs.getLong("min_order_minor"), rs.getInt("eta_min_minutes"),
                rs.getInt("eta_max_minutes"), rs.getBoolean("is_open"), rs.getBoolean("is_synthetic"),
                rs.getString("vertical"), rs.getString("image_url"));
    }

    private static String vertical(String value) {
        if (!"FOOD".equals(value) && !"GROCERY".equals(value)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VERTICAL_INVALID", "vertical must be FOOD or GROCERY");
        }
        return value;
    }

    /** Stores/restaurants of one vertical (default FOOD, so existing clients are unchanged). */
    @GetMapping("/restaurants")
    public ResponseEntity<List<RestaurantSummary>> restaurants(
            @RequestParam(defaultValue = "FOOD") String vertical,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(100000) int offset) {
        List<RestaurantSummary> list = jdbc.query(RESTAURANT_SELECT
                + " where vertical = ? order by is_open desc, sort_order, name, id limit ? offset ?",
                FoodCatalogController::mapRestaurant, vertical(vertical), limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    @GetMapping("/restaurants/{restaurantId}")
    public ResponseEntity<RestaurantDetail> restaurant(@PathVariable UUID restaurantId) {
        RestaurantSummary restaurant = jdbc.query(RESTAURANT_SELECT + " where id = ?",
                FoodCatalogController::mapRestaurant, restaurantId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "RESTAURANT_NOT_FOUND",
                        "Restaurant is not available"));

        Map<UUID, List<Option>> optionsByGroup = new LinkedHashMap<>();
        jdbc.query("""
                select o.id, o.group_id, o.name, o.price_delta_minor
                from marketplace.food_options o
                join marketplace.food_option_groups g on g.id = o.group_id
                join marketplace.food_dishes d on d.id = g.dish_id
                where d.restaurant_id = ? order by o.sort_order, o.name, o.id
                """, rs -> {
                    optionsByGroup.computeIfAbsent(rs.getObject("group_id", UUID.class), k -> new ArrayList<>())
                            .add(new Option(rs.getString("id"), rs.getString("name"), rs.getLong("price_delta_minor")));
                }, restaurantId);

        Map<UUID, List<OptionGroup>> groupsByDish = new LinkedHashMap<>();
        jdbc.query("""
                select g.id, g.dish_id, g.name, g.min_select, g.max_select
                from marketplace.food_option_groups g
                join marketplace.food_dishes d on d.id = g.dish_id
                where d.restaurant_id = ? order by g.sort_order, g.name, g.id
                """, rs -> {
                    UUID groupId = rs.getObject("id", UUID.class);
                    groupsByDish.computeIfAbsent(rs.getObject("dish_id", UUID.class), k -> new ArrayList<>())
                            .add(new OptionGroup(groupId.toString(), rs.getString("name"), rs.getInt("min_select"),
                                    rs.getInt("max_select"), optionsByGroup.getOrDefault(groupId, List.of())));
                }, restaurantId);

        Map<UUID, List<Dish>> dishesBySection = new LinkedHashMap<>();
        jdbc.query("""
                select id, section_id, name, description, price_minor, emoji, tone, available, unit, stock_qty, image_url
                from marketplace.food_dishes where restaurant_id = ? order by sort_order, name, id
                """, rs -> {
                    UUID dishId = rs.getObject("id", UUID.class);
                    String unit = rs.getString("unit");
                    Integer stock = rs.getObject("stock_qty", Integer.class);
                    int limit = "KG".equals(unit) ? 5000 : 20;
                    int maxQuantity = stock == null ? limit : Math.min(limit, stock);
                    dishesBySection.computeIfAbsent(rs.getObject("section_id", UUID.class), k -> new ArrayList<>())
                            .add(new Dish(dishId.toString(), rs.getString("name"), rs.getString("description"),
                                    rs.getLong("price_minor"), rs.getString("emoji"), rs.getString("tone"),
                                    rs.getBoolean("available"), groupsByDish.getOrDefault(dishId, List.of()), unit,
                                    maxQuantity, stock, rs.getString("image_url")));
                }, restaurantId);

        List<Section> sections = jdbc.query("""
                select id, name from marketplace.food_menu_sections where restaurant_id = ? order by sort_order, name, id
                """, (rs, row) -> {
                    UUID id = rs.getObject("id", UUID.class);
                    return new Section(id.toString(), rs.getString("name"), dishesBySection.getOrDefault(id, List.of()));
                }, restaurantId).stream().filter(section -> !section.dishes().isEmpty()).toList();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new RestaurantDetail(restaurant, sections));
    }

    /** Acceptable replacements for a product: same store and unit, available, other than the product itself. */
    @GetMapping("/dishes/{dishId}/alternatives")
    public ResponseEntity<List<DishHit>> alternatives(@PathVariable UUID dishId) {
        List<DishHit> list = jdbc.query("""
                select d.id, d.name, d.description, d.price_minor, d.emoji, d.tone, d.available,
                       r.id as restaurant_id, r.name as restaurant_name
                from marketplace.food_dishes d
                join marketplace.food_restaurants r on r.id = d.restaurant_id
                join marketplace.food_dishes o on o.id = ? and o.restaurant_id = d.restaurant_id
                where d.id <> o.id and d.available and d.unit = o.unit and (d.stock_qty is null or d.stock_qty > 0)
                order by (d.section_id = o.section_id) desc, abs(d.price_minor - o.price_minor), d.name limit 8
                """, (rs, row) -> new DishHit(rs.getString("id"), rs.getString("name"), rs.getString("description"),
                rs.getLong("price_minor"), rs.getString("emoji"), rs.getString("tone"), rs.getBoolean("available"),
                rs.getString("restaurant_id"), rs.getString("restaurant_name")), dishId);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    /** Case-insensitive substring search over restaurant names/cuisine and dish names/descriptions; LIKE wildcards are literal. */
    @GetMapping("/search")
    public ResponseEntity<SearchResult> search(@RequestParam(defaultValue = "") @Size(max = 100) String q,
            @RequestParam(defaultValue = "FOOD") String vertical) {
        vertical(vertical);
        String term = q.strip();
        if (term.isEmpty()) {
            return ResponseEntity.ok(new SearchResult(List.of(), List.of()));
        }
        String contains = "%" + term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        List<RestaurantSummary> restaurants = jdbc.query(RESTAURANT_SELECT
                + " where vertical = ? and (name ilike ? or cuisine ilike ?) order by is_open desc, sort_order, name limit 30",
                FoodCatalogController::mapRestaurant, vertical, contains, contains);
        List<DishHit> dishes = jdbc.query("""
                select d.id, d.name, d.description, d.price_minor, d.emoji, d.tone, d.available,
                       r.id as restaurant_id, r.name as restaurant_name
                from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id
                where r.vertical = ? and (d.name ilike ? or d.description ilike ?)
                order by d.available desc, r.sort_order, d.name limit 50
                """, (rs, row) -> new DishHit(rs.getString("id"), rs.getString("name"), rs.getString("description"),
                rs.getLong("price_minor"), rs.getString("emoji"), rs.getString("tone"), rs.getBoolean("available"),
                rs.getString("restaurant_id"), rs.getString("restaurant_name")), vertical, contains, contains);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new SearchResult(restaurants, dishes));
    }
}
