package kz.kunde.flowers;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
import kz.kunde.platform.ApiException;
import kz.kunde.platform.FeatureToggles;
import kz.kunde.platform.FeatureToggles.Feature;
import kz.kunde.platform.partner.PartnerDirectory;
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
 * Public Flowers &amp; Gifts catalogue (ADR-026): categories, shops, products and the popular showcase.
 * Hidden while FLOWERS is off. A shop is visible when it is synthetic demo data or belongs to an APPROVED partner.
 */
@RestController
@Validated
@RequestMapping("/api/v1/flowers")
public class FlowersCatalogController {
    private final JdbcTemplate db;
    private final FeatureToggles toggles;
    private final PartnerDirectory partners;
    private final FlowersOrderService orders;

    public FlowersCatalogController(JdbcTemplate db, FeatureToggles toggles, PartnerDirectory partners, FlowersOrderService orders) {
        this.db = db;
        this.toggles = toggles;
        this.partners = partners;
        this.orders = orders;
    }

    public record Category(String code, String nameRu, String nameKk, String nameEn, String icon, boolean featured) {}

    public record Shop(String id, String slug, String name, String description, String emoji, String tone, String imageUrl,
            long deliveryFeeMinor, long minOrderMinor, int etaMinMinutes, int etaMaxMinutes, boolean open, boolean synthetic,
            Double latitude, Double longitude, int productCount) {}

    public record Product(String id, String shopId, String shopName, String categoryCode, String name, String description,
            long priceMinor, String emoji, String tone, String imageUrl, boolean available, Integer stockQty, boolean popular) {}

    public record ShopDetail(Shop shop, List<Product> products) {}

    private void requireOn() {
        if (!toggles.enabled(Feature.FLOWERS)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "FLOWERS_DISABLED", "Flowers and gifts is unavailable");
        }
    }

    /** PostgreSQL array literal of ids; an empty set matches nothing. */
    static String arrayLiteral(java.util.Set<UUID> ids) {
        return ids.stream().map(UUID::toString).collect(Collectors.joining(",", "{", "}"));
    }

    private static final String VISIBLE = "(s.is_synthetic or s.partner_id = any(?::uuid[]))";

    private static final String SHOP_SELECT = """
            select s.id, s.slug, s.name, s.description, s.emoji, s.tone, s.image_url, s.delivery_fee_minor, s.min_order_minor,
                   s.eta_min_minutes, s.eta_max_minutes, s.is_open, s.is_synthetic, s.latitude::float8 as latitude,
                   s.longitude::float8 as longitude,
                   (select count(*) from marketplace.flowers_products p where p.shop_id = s.id and p.available) as product_count
            from marketplace.flowers_shops s
            """;

    private static Shop mapShop(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Shop(rs.getString("id"), rs.getString("slug"), rs.getString("name"), rs.getString("description"),
                rs.getString("emoji"), rs.getString("tone"), rs.getString("image_url"), rs.getLong("delivery_fee_minor"),
                rs.getLong("min_order_minor"), rs.getInt("eta_min_minutes"), rs.getInt("eta_max_minutes"), rs.getBoolean("is_open"),
                rs.getBoolean("is_synthetic"), rs.getObject("latitude", Double.class), rs.getObject("longitude", Double.class),
                rs.getInt("product_count"));
    }

    private static final String PRODUCT_SELECT = """
            select p.id, p.shop_id, s.name as shop_name, p.category_code, p.name, p.description, p.price_minor, p.emoji, p.tone,
                   p.image_url, p.available, p.stock_qty, p.popular
            from marketplace.flowers_products p join marketplace.flowers_shops s on s.id = p.shop_id
            """;

    private static Product mapProduct(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Product(rs.getString("id"), rs.getString("shop_id"), rs.getString("shop_name"), rs.getString("category_code"),
                rs.getString("name"), rs.getString("description"), rs.getLong("price_minor"), rs.getString("emoji"),
                rs.getString("tone"), rs.getString("image_url"), rs.getBoolean("available"), rs.getObject("stock_qty", Integer.class),
                rs.getBoolean("popular"));
    }

    @GetMapping("/categories")
    public ResponseEntity<List<Category>> categories(
            @RequestParam(required = false) Boolean featured,
            @RequestParam(defaultValue = "20") @Min(1) @Max(50) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(10000) int offset) {
        requireOn();
        var categories = db.query("""
                select code, name_ru, name_kk, name_en, icon, featured
                from marketplace.flowers_categories
                where active and (?::boolean is null or featured = ?)
                order by sort_order, code limit ? offset ?
                """, (rs, row) -> new Category(rs.getString("code"), rs.getString("name_ru"), rs.getString("name_kk"),
                rs.getString("name_en"), rs.getString("icon"), rs.getBoolean("featured")), featured, featured, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(categories);
    }

    /** Shops, open first; {@code category} keeps only shops that sell an available product of that category, {@code q} matches name or description. */
    @GetMapping("/shops")
    public ResponseEntity<List<Shop>> shops(
            @RequestParam(required = false) @Size(max = 32) String category,
            @RequestParam(required = false) @Size(max = 80) String q,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(100000) int offset) {
        requireOn();
        String term = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        var shops = db.query(SHOP_SELECT + " where " + VISIBLE + """
                 and (?::text is null or exists (select 1 from marketplace.flowers_products p
                        where p.shop_id = s.id and p.available and p.category_code = ?))
                 and (?::text is null or lower(s.name) like ? or lower(s.description) like ?)
                order by s.is_open desc, s.sort_order, s.name, s.id limit ? offset ?
                """, FlowersCatalogController::mapShop, arrayLiteral(partners.approvedPartnerIds()), category, category,
                term, term, term, limit, offset);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(shops);
    }

    @GetMapping("/shops/{id}")
    public ResponseEntity<ShopDetail> shop(@PathVariable UUID id) {
        requireOn();
        var found = db.query(SHOP_SELECT + " where s.id = ? and " + VISIBLE, FlowersCatalogController::mapShop, id,
                arrayLiteral(partners.approvedPartnerIds()));
        if (found.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "FLOWERS_SHOP_NOT_FOUND", "Shop not found");
        }
        var products = db.query(PRODUCT_SELECT + " where p.shop_id = ? order by p.category_code, p.sort_order, p.name, p.id",
                FlowersCatalogController::mapProduct, id);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new ShopDetail(found.get(0), products));
    }

    /** Showcase for the home screen: products marked popular, available, from visible and open shops. */
    @GetMapping("/products/popular")
    public ResponseEntity<List<Product>> popular(@RequestParam(defaultValue = "10") @Min(1) @Max(30) int limit) {
        requireOn();
        var products = db.query(PRODUCT_SELECT + " where p.popular and p.available and s.is_open and " + VISIBLE
                + " order by p.sort_order, p.name, p.id limit ?", FlowersCatalogController::mapProduct,
                arrayLiteral(partners.approvedPartnerIds()), limit);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(products);
    }

    /** Delivery windows of one local date (Asia/Almaty) for the «к определённому времени» mode. */
    @GetMapping("/delivery-slots")
    public ResponseEntity<List<FlowersOrderService.Slot>> deliverySlots(
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate date) {
        requireOn();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(orders.slots(date, java.time.Instant.now()));
    }
}
