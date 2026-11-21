package kz.kunde.groceries;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
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

/**
 * Public read-only Groceries catalog: product categories, server-side product search/filters/sorting, brands and the
 * product page. Stores and products live in the Food tables with {@code vertical = 'GROCERY'}. Everything is
 * unavailable (409 GROCERIES_DISABLED) while the GROCERIES switch is off. There is no product rating filter or sort:
 * ratings exist per store, not per product, and no product ratings are invented.
 */
@RestController
@Validated
@RequestMapping("/api/v1/groceries")
@ConditionalOnProperty(name = "app.food.enabled", havingValue = "true")
public class GroceriesCatalogController {
    private static final int NEW_DAYS = 14;

    public record Category(String slug, String nameRu, String nameKk, String nameEn, String icon, int products) {}

    public record Product(String id, String name, String description, String brand, String category, String unit,
            long priceMinor, Long compareAtPriceMinor, Integer discountPercent, boolean available, boolean inStock,
            int maxQuantity, Integer stockQty, String emoji, String tone, String imageUrl, String storeId,
            String storeName, boolean storeOpen, boolean isNew, boolean onSale, boolean hasRequiredOptions) {}

    public record ProductsPage(List<Product> items, long total, int limit, int offset) {}

    public record Nutrition(Integer kcal, Double protein, Double fat, Double carbs) {}

    public record Option(String id, String name, long priceDeltaMinor) {}

    public record OptionGroup(String id, String name, int minSelect, int maxSelect, List<Option> options) {}

    public record ProductDetail(Product product, String composition, String storageConditions, String originCountry,
            Nutrition nutrition, int minQuantity, int quantityStep, List<OptionGroup> optionGroups,
            List<Product> related, List<String> images) {}

    private static final Map<String, String> SORTS = Map.of(
            "popularity", "popularity desc, d.name, d.id",
            "price_asc", "d.price_minor asc, d.name, d.id",
            "price_desc", "d.price_minor desc, d.name, d.id",
            "new", "d.created_at desc, d.name, d.id",
            "discount", "((d.compare_at_price_minor - d.price_minor)::float8 / nullif(d.compare_at_price_minor, 0)) desc nulls last, d.name, d.id");

    static final String PRODUCT_SELECT = """
            select d.id, d.name, d.description, d.brand, d.grocery_category, d.unit, d.price_minor, d.compare_at_price_minor,
                   d.available, d.stock_qty, d.emoji, d.tone, d.image_url, d.created_at,
                   r.id as store_id, r.name as store_name, (r.is_open and r.moderation_status = 'ACTIVE') as store_open,
                   exists (select 1 from marketplace.food_option_groups g where g.dish_id = d.id and g.min_select > 0) as has_required_options,
                   (select count(distinct i.order_id) from transactions.food_order_items i
                      join transactions.food_orders o on o.id = i.order_id
                     where i.dish_id = d.id and o.status <> 'CANCELLED') as popularity
            from marketplace.food_dishes d
            join marketplace.food_restaurants r on r.id = d.restaurant_id
            """;

    private final JdbcTemplate db;
    private final FeatureToggles toggles;

    public GroceriesCatalogController(JdbcTemplate db, FeatureToggles toggles) {
        this.db = db;
        this.toggles = toggles;
    }

    static void requireEnabled(FeatureToggles toggles) {
        if (!toggles.enabled(FeatureToggles.Feature.GROCERIES)) {
            throw new ApiException(HttpStatus.CONFLICT, "GROCERIES_DISABLED", "Groceries is switched off");
        }
    }

    static int maxQuantity(String unit, Integer stock) {
        int limit = "KG".equals(unit) ? 5000 : 20;
        return stock == null ? limit : Math.max(0, Math.min(limit, stock));
    }

    static Product mapProduct(ResultSet rs, int row) throws SQLException {
        String unit = rs.getString("unit");
        Integer stock = rs.getObject("stock_qty", Integer.class);
        boolean available = rs.getBoolean("available");
        long price = rs.getLong("price_minor");
        Long compareAt = rs.getObject("compare_at_price_minor", Long.class);
        Integer percent = compareAt == null ? null : (int) Math.round((compareAt - price) * 100.0 / compareAt);
        OffsetDateTime created = rs.getObject("created_at", OffsetDateTime.class);
        boolean inStock = available && (stock == null || stock > 0);
        return new Product(rs.getString("id"), rs.getString("name"), rs.getString("description"), rs.getString("brand"),
                rs.getString("grocery_category"), unit, price, compareAt, percent, available, inStock,
                maxQuantity(unit, stock), stock, rs.getString("emoji"), rs.getString("tone"), rs.getString("image_url"),
                rs.getString("store_id"), rs.getString("store_name"), rs.getBoolean("store_open"),
                created != null && created.isAfter(OffsetDateTime.now().minusDays(NEW_DAYS)), compareAt != null,
                rs.getBoolean("has_required_options"));
    }

    private static Double dbl(java.math.BigDecimal value) { return value == null ? null : value.doubleValue(); }

    private static String like(String term) {
        return "%" + term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
    }

    @GetMapping("/categories")
    public ResponseEntity<List<Category>> categories() {
        requireEnabled(toggles);
        List<Category> list = db.query("""
                select c.slug, c.name_ru, c.name_kk, c.name_en, c.icon,
                       (select count(*) from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id
                         where d.grocery_category = c.slug and r.vertical = 'GROCERY' and r.moderation_status = 'ACTIVE' and d.available) as products
                from marketplace.grocery_categories c where c.enabled order by c.sort_order, c.slug
                """, (rs, row) -> new Category(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4),
                rs.getString(5), rs.getInt(6)));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    @GetMapping("/brands")
    public ResponseEntity<List<String>> brands(@RequestParam(required = false) @Size(max = 32) String category,
            @RequestParam(required = false) UUID storeId) {
        requireEnabled(toggles);
        StringBuilder where = new StringBuilder(" where r.vertical = 'GROCERY' and r.moderation_status = 'ACTIVE' and d.brand is not null");
        List<Object> args = new ArrayList<>();
        if (category != null && !category.isBlank()) { where.append(" and d.grocery_category = ?"); args.add(category); }
        if (storeId != null) { where.append(" and r.id = ?"); args.add(storeId); }
        List<String> list = db.queryForList("select distinct d.brand from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id"
                + where + " order by d.brand limit 100", String.class, args.toArray());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(list);
    }

    /**
     * Products with server-side search (name, brand, description, category name), filters (category, store, price range,
     * in stock, on sale, brand, new) and sorting (popularity = number of non-cancelled orders containing the product,
     * price, new, discount). Unavailable products are listed last unless {@code inStock=true}.
     */
    @GetMapping("/products")
    public ResponseEntity<ProductsPage> products(
            @RequestParam(required = false) @Size(max = 100) String q,
            @RequestParam(required = false) @Size(max = 32) String category,
            @RequestParam(required = false) UUID storeId,
            @RequestParam(required = false) @Min(0) @Max(100000000) Long minPriceMinor,
            @RequestParam(required = false) @Min(0) @Max(100000000) Long maxPriceMinor,
            @RequestParam(required = false) Boolean inStock,
            @RequestParam(required = false) Boolean onSale,
            @RequestParam(required = false) Boolean newOnly,
            @RequestParam(required = false) @Size(max = 80) String brand,
            @RequestParam(defaultValue = "popularity") String sort,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(100000) int offset) {
        requireEnabled(toggles);
        String orderBy = SORTS.get(sort);
        if (orderBy == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "SORT_INVALID", "sort must be popularity, price_asc, price_desc, new or discount");
        }
        if (minPriceMinor != null && maxPriceMinor != null && minPriceMinor > maxPriceMinor) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PRICE_RANGE_INVALID", "minPriceMinor must not exceed maxPriceMinor");
        }
        StringBuilder where = new StringBuilder(" where r.vertical = 'GROCERY' and r.moderation_status = 'ACTIVE'");
        List<Object> args = new ArrayList<>();
        if (q != null && !q.isBlank()) {
            String term = like(q.strip());
            where.append(" and (d.name ilike ? or d.brand ilike ? or d.description ilike ? or exists (select 1 from marketplace.grocery_categories c"
                    + " where c.slug = d.grocery_category and (c.name_ru ilike ? or c.name_en ilike ? or c.name_kk ilike ?)))");
            for (int i = 0; i < 6; i++) { args.add(term); }
        }
        if (category != null && !category.isBlank()) {
            if ("other".equals(category)) { where.append(" and d.grocery_category is null"); }
            else { where.append(" and d.grocery_category = ?"); args.add(category); }
        }
        if (storeId != null) { where.append(" and r.id = ?"); args.add(storeId); }
        if (minPriceMinor != null) { where.append(" and d.price_minor >= ?"); args.add(minPriceMinor); }
        if (maxPriceMinor != null) { where.append(" and d.price_minor <= ?"); args.add(maxPriceMinor); }
        if (Boolean.TRUE.equals(inStock)) { where.append(" and d.available and (d.stock_qty is null or d.stock_qty > 0)"); }
        if (Boolean.TRUE.equals(onSale)) { where.append(" and d.compare_at_price_minor is not null"); }
        if (Boolean.TRUE.equals(newOnly)) { where.append(" and d.created_at > now() - interval '" + NEW_DAYS + " days'"); }
        if (brand != null && !brand.isBlank()) { where.append(" and d.brand = ?"); args.add(brand.strip()); }

        Long total = db.queryForObject("select count(*) from marketplace.food_dishes d join marketplace.food_restaurants r on r.id = d.restaurant_id"
                + where, Long.class, args.toArray());
        List<Object> pageArgs = new ArrayList<>(args);
        pageArgs.add(limit);
        pageArgs.add(offset);
        List<Product> items = db.query(PRODUCT_SELECT + where
                + " order by (d.available and (d.stock_qty is null or d.stock_qty > 0)) desc, " + orderBy + " limit ? offset ?",
                GroceriesCatalogController::mapProduct, pageArgs.toArray());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new ProductsPage(items, total == null ? 0 : total, limit, offset));
    }

    @GetMapping("/products/{productId}")
    public ResponseEntity<ProductDetail> product(@PathVariable UUID productId) {
        requireEnabled(toggles);
        Product product = db.query(PRODUCT_SELECT + " where d.id = ? and r.vertical = 'GROCERY' and r.moderation_status = 'ACTIVE'",
                GroceriesCatalogController::mapProduct, productId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "PRODUCT_NOT_FOUND", "Product is not available"));
        var extra = db.query("""
                select composition, storage_conditions, origin_country, kcal_100, protein_100, fat_100, carbs_100
                from marketplace.food_dishes where id = ?
                """, (rs, row) -> new Object[] {rs.getString(1), rs.getString(2), rs.getString(3),
                        rs.getObject(4, Integer.class), dbl(rs.getBigDecimal(5)), dbl(rs.getBigDecimal(6)),
                        dbl(rs.getBigDecimal(7))}, productId).get(0);
        Nutrition nutrition = extra[3] == null && extra[4] == null && extra[5] == null && extra[6] == null ? null
                : new Nutrition((Integer) extra[3], (Double) extra[4], (Double) extra[5], (Double) extra[6]);

        Map<UUID, List<Option>> optionsByGroup = new LinkedHashMap<>();
        db.query("""
                select o.id, o.group_id, o.name, o.price_delta_minor
                from marketplace.food_options o join marketplace.food_option_groups g on g.id = o.group_id
                where g.dish_id = ? order by o.sort_order, o.name, o.id
                """, rs -> {
                    optionsByGroup.computeIfAbsent(rs.getObject("group_id", UUID.class), k -> new ArrayList<>())
                            .add(new Option(rs.getString("id"), rs.getString("name"), rs.getLong("price_delta_minor")));
                }, productId);
        List<OptionGroup> groups = db.query("""
                select id, name, min_select, max_select from marketplace.food_option_groups
                where dish_id = ? order by sort_order, name, id
                """, (rs, row) -> new OptionGroup(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getInt(4),
                optionsByGroup.getOrDefault(rs.getObject(1, UUID.class), List.of())), productId);
        List<Product> related = db.query(PRODUCT_SELECT + """
                 where r.vertical = 'GROCERY' and r.moderation_status = 'ACTIVE' and d.id <> ?
                   and d.available and (d.stock_qty is null or d.stock_qty > 0)
                   and (r.id = ?::uuid or d.grocery_category = ?::varchar)
                 order by (r.id = ?::uuid) desc, (d.grocery_category is not distinct from ?::varchar) desc, popularity desc, d.name limit 6
                """, GroceriesCatalogController::mapProduct, productId, product.storeId(), product.category(),
                product.storeId(), product.category());
        List<String> images = db.queryForList("select url from marketplace.food_dish_photos where dish_id = ? order by sort_order, created_at, id",
                String.class, productId);
        if (images.isEmpty() && product.imageUrl() != null) { images = List.of(product.imageUrl()); }
        boolean kg = "KG".equals(product.unit());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new ProductDetail(product,
                (String) extra[0], (String) extra[1], (String) extra[2], nutrition, kg ? 100 : 1, kg ? 100 : 1, groups, related, images));
    }
}
