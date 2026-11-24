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
            int etaMaxMinutes, boolean open, boolean synthetic, String vertical, String imageUrl, Double ratingAvg,
            int ratingCount, boolean pickupEnabled, int prepMinutes, String addressText, boolean hasPromo) {}

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

    private kz.kunde.platform.FeatureToggles toggles;

    public FoodCatalogController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @org.springframework.beans.factory.annotation.Autowired
    void setToggles(kz.kunde.platform.FeatureToggles toggles) { this.toggles = toggles; }

    private void requireGroceriesOn(String vertical) {
        if ("GROCERY".equals(vertical) && toggles != null && !toggles.enabled(kz.kunde.platform.FeatureToggles.Feature.GROCERIES)) {
            throw new ApiException(HttpStatus.CONFLICT, "GROCERIES_DISABLED", "Groceries is switched off");
        }
    }

    static final String RESTAURANT_SELECT = """
            select id, slug, name, cuisine, description, emoji, tone, delivery_fee_minor, min_order_minor,
                   eta_min_minutes, eta_max_minutes, (is_open and moderation_status = 'ACTIVE') as is_open, is_synthetic, vertical, image_url,
                   (select round(avg(v.rating)::numeric, 1)::float8 from marketplace.food_reviews v
                     where v.restaurant_id = r.id and v.status = 'VISIBLE') as rating_avg,
                   (select count(*) from marketplace.food_reviews v
                     where v.restaurant_id = r.id and v.status = 'VISIBLE') as rating_count,
                   pickup_enabled, prep_minutes, address_text,
                   exists (select 1 from marketplace.food_promotions p
                            where p.status = 'ACTIVE' and p.starts_at <= now() and p.ends_at > now()
                              and (p.restaurant_id = r.id or (p.restaurant_id is null and (p.cuisine is null or p.cuisine = r.cuisine)))) as has_promo
            from marketplace.food_restaurants r
            """;

    static RestaurantSummary mapRestaurant(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new RestaurantSummary(rs.getString("id"), rs.getString("slug"), rs.getString("name"),
                rs.getString("cuisine"), rs.getString("description"), rs.getString("emoji"), rs.getString("tone"),
                rs.getLong("delivery_fee_minor"), rs.getLong("min_order_minor"), rs.getInt("eta_min_minutes"),
                rs.getInt("eta_max_minutes"), rs.getBoolean("is_open"), rs.getBoolean("is_synthetic"),
                rs.getString("vertical"), rs.getString("image_url"), rs.getObject("rating_avg", Double.class),
                rs.getInt("rating_count"), rs.getBoolean("pickup_enabled"), rs.getInt("prep_minutes"),
                rs.getString("address_text"), rs.getBoolean("has_promo"));
    }

    private static String vertical(String value) {
        if (!"FOOD".equals(value) && !"GROCERY".equals(value) && !"FLOWERS_GIFTS".equals(value)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VERTICAL_INVALID", "vertical must be FOOD, GROCERY or FLOWERS_GIFTS");
        }
        return value;
    }

    private static final java.util.Map<String, String> SORTS = java.util.Map.of(
            "recommended", "(r.is_open and r.moderation_status = 'ACTIVE') desc, r.sort_order, r.name, r.id",
            "rating", "(r.is_open and r.moderation_status = 'ACTIVE') desc, rating_avg desc nulls last, rating_count desc, r.name, r.id",
            "delivery_fee", "(r.is_open and r.moderation_status = 'ACTIVE') desc, r.delivery_fee_minor, r.name, r.id",
            "eta", "(r.is_open and r.moderation_status = 'ACTIVE') desc, r.eta_min_minutes, r.name, r.id");

    /**
     * Stores/restaurants of one vertical (default FOOD, so existing clients are unchanged), with server-side filters
     * (open now, pickup, free delivery, promotion, minimum rating, cuisine, price range by minimum order) and sorting.
     * Distance sorting is not offered: restaurants have no stored coordinates yet, so no distance is invented.
     */
    @GetMapping("/restaurants")
    public ResponseEntity<List<RestaurantSummary>> restaurants(
            @RequestParam(defaultValue = "FOOD") String vertical,
            @RequestParam(required = false) Boolean openNow,
            @RequestParam(required = false) Boolean pickup,
            @RequestParam(required = false) Boolean freeDelivery,
            @RequestParam(required = false) Boolean promo,
            @RequestParam(required = false) @Min(1) @Max(5) Integer minRating,
            @RequestParam(required = false) @Size(max = 80) String cuisine,
            @RequestParam(required = false) @Min(0) @Max(100000000) Long maxMinOrderMinor,
            @RequestParam(defaultValue = "recommended") String sort,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(100000) int offset) {
        String orderBy = SORTS.get(sort);
        if (orderBy == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "SORT_INVALID", "sort must be recommended, rating, delivery_fee or eta");
        }
        requireGroceriesOn(vertical);
        StringBuilder where = new StringBuilder(" where r.vertical = ?");
        List<Object> args = new ArrayList<>();
        args.add(vertical(vertical));
        if (Boolean.TRUE.equals(openNow)) { where.append(" and (r.is_open and r.moderation_status = 'ACTIVE')"); }
        if (Boolean.TRUE.equals(pickup)) { where.append(" and r.pickup_enabled"); }
        if (Boolean.TRUE.equals(freeDelivery)) { where.append(" and r.delivery_fee_minor = 0"); }
        if (Boolean.TRUE.equals(promo)) {
            where.append(" and exists (select 1 from marketplace.food_promotions p where p.status = 'ACTIVE' and p.starts_at <= now()"
                    + " and p.ends_at > now() and (p.restaurant_id = r.id or (p.restaurant_id is null and (p.cuisine is null or p.cuisine = r.cuisine))))");
        }
        if (minRating != null) {
            where.append(" and (select avg(v.rating) from marketplace.food_reviews v where v.restaurant_id = r.id and v.status = 'VISIBLE') >= ?");
            args.add(minRating);
        }
        if (cuisine != null && !cuisine.isBlank()) { where.append(" and r.cuisine = ?"); args.add(cuisine.strip()); }
        if (maxMinOrderMinor != null) { where.append(" and r.min_order_minor <= ?"); args.add(maxMinOrderMinor); }
        args.add(limit);
        args.add(offset);
        List<RestaurantSummary> list = jdbc.query(RESTAURANT_SELECT + where + " order by " + orderBy + " limit ? offset ?",
                FoodCatalogController::mapRestaurant, args.toArray());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    @GetMapping("/restaurants/{restaurantId}")
    public ResponseEntity<RestaurantDetail> restaurant(@PathVariable UUID restaurantId) {
        RestaurantSummary restaurant = jdbc.query(RESTAURANT_SELECT + " where r.id = ?",
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
        requireGroceriesOn(vertical);
        String term = q.strip();
        if (term.isEmpty()) {
            return ResponseEntity.ok(new SearchResult(List.of(), List.of()));
        }
        String contains = "%" + term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        List<RestaurantSummary> restaurants = jdbc.query(RESTAURANT_SELECT
                + " where r.vertical = ? and (r.name ilike ? or r.cuisine ilike ?) order by (r.is_open and r.moderation_status = 'ACTIVE') desc, r.sort_order, r.name limit 30",
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
